#!/usr/bin/env python3
"""Compare local MOTIS and OTP with identical points/times; no third-party Python deps."""
import argparse
import datetime as dt
import json
from pathlib import Path
import statistics
import subprocess
from urllib.parse import urlencode

QUERY = '''query PlanConnection($origin: PlanLabeledLocationInput!, $destination: PlanLabeledLocationInput!, $dateTime: PlanDateTimeInput!, $modes: PlanModesInput) {
  planConnection(origin: $origin, destination: $destination, dateTime: $dateTime, modes: $modes, first: 100, searchWindow: "PT1H") {
    edges { node { startTime endTime duration numberOfTransfers legs {
      mode duration startTime endTime distance from { name lat lon } to { name lat lon }
      route { shortName longName } legGeometry { points }
    } } }
  }
}'''
TRANSIT = 'AIRPLANE BUS CABLE_CAR COACH FERRY FUNICULAR GONDOLA MONORAIL RAIL SUBWAY TRAM TROLLEYBUS'.split()
PARK = [52.4884438, 13.4703145]
SCHOENEWEIDE = [52.4548738, 13.5092508]
ALEX = [52.5219, 13.4132]
HBF = [52.5251, 13.3694]
ZOO = [52.5073, 13.3324]
CASES = [
    dict(id='park_schoeneweide', origin=PARK, destination=SCHOENEWEIDE),
    dict(id='alex_hbf', origin=ALEX, destination=HBF),
    dict(id='park_zoo', origin=PARK, destination=ZOO),
    dict(id='night', origin=PARK, destination=ZOO, time='2026-09-08T00:00:00Z'),
    dict(id='arrive_by', origin=PARK, destination=ZOO, arrive_by=True),
    dict(id='outside_region', origin=[48.137, 11.575], destination=HBF, negative=True),
    dict(id='expired_timetable', origin=PARK, destination=ZOO, time='2027-01-15T08:00:00Z', negative=True),
]


def request(client, url, body=None):
    cmd = ['docker', 'exec', client, 'curl', '-sS', '--max-time', '45', '-w', '\n%{time_total}\n%{http_code}']
    if body is not None:
        cmd += ['-H', 'Content-Type: application/json', '-d', json.dumps(body)]
    result = subprocess.run(cmd + [url], capture_output=True, text=True, timeout=50)
    if result.returncode:
        return {'transport_error': result.stderr.strip()}, None, None
    text, seconds, code = result.stdout.rsplit('\n', 2)
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        payload = {'invalid_json': text[:500]}
    return payload, float(seconds) * 1000, int(code)


def query_case(args, engine, case):
    timestamp = case.get('time', '2026-09-07T08:00:00Z')
    arrive = case.get('arrive_by', False)
    if engine == 'motis':
        params = dict(fromPlace=','.join(map(str, case['origin'])), toPlace=','.join(map(str, case['destination'])),
                      time=timestamp, arriveBy=str(arrive).lower(), transitModes='TRANSIT', directModes='WALK',
                      preTransitModes='WALK', postTransitModes='WALK', useRoutedTransfers='true',
                      detailedLegs='true', detailedTransfers='true', timetableView='true',
                      searchWindow=3600, numItineraries=1, maxItineraries=100)
        return request(args.client_container, args.motis_url + '/api/v6/plan?' + urlencode(params))
    def location(pair):
        return {'location': {'coordinate': dict(latitude=pair[0], longitude=pair[1])}}
    body = {'query': QUERY, 'variables': {
        'origin': location(case['origin']), 'destination': location(case['destination']),
        'dateTime': {'latestArrival' if arrive else 'earliestDeparture': timestamp},
        'modes': {'direct': ['WALK'], 'transit': {'transit': [{'mode': m} for m in TRANSIT]}}
    }}
    return request(args.client_container, args.otp_url + '/otp/gtfs/v1', body)


def decode(shape, precision):
    values = []
    value = shift = 0
    for char in shape:
        byte = ord(char) - 63
        if not 0 <= byte <= 63:
            raise ValueError('invalid polyline byte')
        value |= (byte & 31) << shift
        if byte < 32:
            values.append(~(value >> 1) if value & 1 else value >> 1)
            value = shift = 0
        else:
            shift += 5
    if shift or len(values) % 2:
        raise ValueError('truncated polyline')
    lat = lon = 0
    coords = []
    for i in range(0, len(values), 2):
        lat += values[i]
        lon += values[i + 1]
        coords.append([lat / 10 ** precision, lon / 10 ** precision])
    return coords


def summarize(engine, body):
    if engine == 'motis':
        itineraries = body.get('itineraries', [])
    else:
        connection = (body.get('data') or {}).get('planConnection') or {}
        itineraries = [e['node'] for e in connection.get('edges', [])]
    result = []
    for it in itineraries:
        legs = it.get('legs', [])
        if not any(leg.get('mode') not in ['WALK', 'BIKE', 'BICYCLE', 'CAR', None] for leg in legs):
            continue
        geometries = []
        for leg in legs:
            geom = leg.get('legGeometry') or {}
            try:
                points = decode(geom.get('points', ''), geom.get('precision', 6 if engine == 'motis' else 5))
                valid = len(points) >= 2 and all(-90 <= lat <= 90 and -180 <= lon <= 180 for lat, lon in points)
                in_berlin_area = bool(points) and all(51.5 <= lat <= 53.5 and 12 <= lon <= 15 for lat, lon in points)
            except ValueError:
                points, valid, in_berlin_area = [], False, False
            geometries.append(dict(mode=leg.get('mode'), points=len(points), valid=valid,
                                   in_berlin_area=in_berlin_area))
        result.append(dict(duration_s=it.get('duration'), departure=it.get('startTime'), arrival=it.get('endTime'),
                           transfers=it.get('transfers', it.get('numberOfTransfers')),
                           modes=[l.get('mode') for l in legs],
                           lines=[l.get('routeShortName') or (l.get('route') or {}).get('shortName') for l in legs if l.get('mode') != 'WALK'],
                           geometry=geometries))
    return sorted(result, key=lambda i: i['duration_s'] or 0)


def validate(rows):
    for row in rows:
        for sample in row['samples']:
            if sample['http_status'] not in ([200] if row['expected_transit'] else [200, 400]):
                raise RuntimeError(f"Unexpected HTTP result: {row['case']['id']} {row['engine']} {sample}")
            if bool(sample['transit_count']) != row['expected_transit']:
                raise RuntimeError(f"Unexpected transit availability: {row['case']['id']} {row['engine']}")
        limit = dt.datetime.fromisoformat(row['case'].get('time', '2026-09-07T08:00:00Z'))
        arrive_by = row['case'].get('arrive_by', False)
        for itinerary in row['itineraries']:
            for geometry in itinerary['geometry']:
                if not geometry['valid'] or not geometry['in_berlin_area']:
                    raise RuntimeError(f"Invalid geometry: {row['case']['id']} {row['engine']} {geometry}")
            value = itinerary['arrival' if arrive_by else 'departure']
            timestamp = dt.datetime.fromtimestamp(value / 1000, dt.timezone.utc) if isinstance(value, (int, float)) else dt.datetime.fromisoformat(value)
            valid = timestamp <= limit if arrive_by else timestamp >= limit
            if not valid:
                raise RuntimeError(f"Time constraint violated: {row['case']['id']} {row['engine']}")


def direct_smoke(args):
    rows = []
    for mode in ['WALK', 'BIKE', 'CAR']:
        params = dict(fromPlace=','.join(map(str, PARK)), toPlace=','.join(map(str, SCHOENEWEIDE)),
                      time='2026-09-07T08:00:00Z', transitModes='', directModes=mode, maxDirectTime=7200)
        body, ms, status = request(args.client_container, args.motis_url + '/api/v6/plan?' + urlencode(params))
        direct = body.get('direct', [])
        geometries = [leg.get('legGeometry') or {} for it in direct for leg in it['legs']]
        valid = bool(geometries) and all(len(decode(g.get('points', ''), g.get('precision', 6))) >= 2 for g in geometries)
        row = dict(mode=mode, http_status=status, ms=ms, count=len(direct),
                   duration_s=[it.get('duration') for it in direct], geometry_valid=valid)
        if status != 200 or not direct or not valid:
            raise RuntimeError(f'Direct route smoke failed: {row}')
        rows.append(row)
        (args.output / f'direct-{mode.lower()}.json').write_text(json.dumps(body, indent=2))
    (args.output / 'direct-summary.json').write_text(json.dumps(rows, indent=2))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client-container', default='atlas-app')
    parser.add_argument('--motis-url', default='http://motis-experiment:8080')
    parser.add_argument('--otp-url', default='http://apo-otp:8080')
    parser.add_argument('--direct-only', action='store_true', help='Only smoke-test MOTIS street routing')
    parser.add_argument('--samples', type=int, default=5)
    parser.add_argument('--output', type=Path, default=Path('data/motis-benchmark/results'))
    args = parser.parse_args()
    if args.samples < 1:
        parser.error('--samples must be positive')
    args.output.mkdir(parents=True, exist_ok=True)
    if args.direct_only:
        print(json.dumps(direct_smoke(args), indent=2))
        return
    rows = []
    for case in CASES:
        samples = {engine: [] for engine in ['motis', 'otp']}
        payloads = {}
        # First call excluded as a per-case warmup; alternate engine order.
        for sample in range(args.samples + 1):
            for engine in (['motis', 'otp'] if sample % 2 == 0 else ['otp', 'motis']):
                body, elapsed, code = query_case(args, engine, case)
                payloads[engine] = body
                samples[engine].append(dict(http_status=code, ms=elapsed,
                    transit_count=len(summarize(engine, body)), error=body.get('errors') or body.get('error') or body.get('transport_error')))
        for engine in ['motis', 'otp']:
            body = payloads[engine]
            timed = samples[engine][1:]
            times = [s['ms'] for s in timed if s['ms'] is not None]
            itins = summarize(engine, body)
            row = dict(case=case, engine=engine, warmup=samples[engine][0], samples=timed,
                       median_ms=statistics.median(times) if times else None,
                       max_ms=max(times) if times else None, itineraries=itins,
                       expected_transit=not case.get('negative', False))
            rows.append(row)
            (args.output / f"{case['id']}-{engine}.json").write_text(json.dumps(body, indent=2))
            print(f"{case['id']} {engine}: {len(itins)} transit alternatives, median {row['median_ms']:.1f} ms", flush=True)
        (args.output / 'summary.json').write_text(json.dumps(dict(recorded_at=dt.datetime.now(dt.timezone.utc).isoformat(), search_window_seconds=3600, max_itineraries=100, rows=rows), indent=2))

    validate(rows)
    direct_smoke(args)
    print("All transit, geometry, time constraint and street routing checks passed.")


if __name__ == '__main__':
    main()
