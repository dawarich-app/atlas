defmodule AtlasWeb.SearchCardTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AtlasWeb.SearchCard

  defp card(overrides) do
    defaults = %{
      id: "search-card",
      query: "leipzig",
      results: [],
      status: "unavailable",
      service: "photon",
      snapshot: nil,
      active: -1,
      searched: true
    }

    render_component(&SearchCard.search_card/1, Map.merge(defaults, overrides))
  end

  describe "when the backing service was never installed" do
    test "names the tool instead of saying 'unavailable'" do
      # "Search unavailable" tells a self-hoster nothing they can act on. The
      # geocoding profile simply was never started, and the copy must say so.
      html = card(%{snapshot: nil})

      assert html =~ "Photon is not installed"
      refute html =~ "not responding"
    end

    test "a switched-off service reads the same as one never seen" do
      html = card(%{snapshot: %{enabled?: false, status: :ready}})

      assert html =~ "Photon is not installed"
    end

    test "points at the place where it can be installed" do
      assert card(%{snapshot: nil}) =~ "/admin/services"
    end

    test "names whichever service was passed, not a hardcoded one" do
      html = card(%{service: "valhalla", snapshot: nil})

      assert html =~ "Valhalla is not installed"
      refute html =~ "Photon"
    end
  end

  describe "when the service is still coming up" do
    test "says it is installing rather than blaming the search" do
      html =
        card(%{snapshot: %{enabled?: true, status: :downloading, progress: 0.42, phase: "index"}})

      assert html =~ "Photon is still installing"
      refute html =~ "not installed"
      refute html =~ "not responding"
    end

    test "shows how far along it is, so waiting is an informed choice" do
      html = card(%{snapshot: %{enabled?: true, status: :downloading, progress: 0.42}})

      assert html =~ "42%"
    end
  end

  describe "when the service is installed and up but did not answer" do
    test "reports a fault, not a missing install" do
      html = card(%{snapshot: %{enabled?: true, status: :ready}})

      assert html =~ "Photon is not responding"
      refute html =~ "not installed"
    end
  end

  describe "when the search itself succeeded" do
    test "an empty result set says so, and never blames the service" do
      html = card(%{status: "ok", results: [], snapshot: %{enabled?: true, status: :ready}})

      assert html =~ "No results"
      assert html =~ "leipzig"
      refute html =~ "not installed"
      refute html =~ "not responding"
    end

    test "results render as a list" do
      results = [%{id: "1", label: "Leipzig, Germany"}]
      html = card(%{status: "ok", results: results, snapshot: %{enabled?: true, status: :ready}})

      assert html =~ "Leipzig, Germany"
      refute html =~ "No results"
    end

    test "results win even while the service reports trouble" do
      # A stale-but-rendered result list beats replacing it with an error the
      # user cannot act on.
      results = [%{id: "1", label: "Leipzig, Germany"}]
      html = card(%{status: "ok", results: results, snapshot: nil})

      assert html =~ "Leipzig, Germany"
      refute html =~ "not installed"
    end
  end

  describe "row states must be visible" do
    # The whole panel sits on `bg-base-200` (MapLive's root div), so painting a
    # row `bg-base-200` — or that colour at any alpha — paints it the exact
    # shade it already was. Both the hover and the highlight did that, which is
    # why neither could be seen. Asserting the class names is the cheap guard;
    # the real one is measuring computed colour in a browser.
    @backdrop "bg-base-200"

    test "the highlighted row is not tinted with the backdrop colour" do
      results = [%{id: "1", label: "A"}, %{id: "2", label: "B"}]

      html =
        card(%{
          status: "ok",
          results: results,
          active: 1,
          snapshot: %{enabled?: true, status: :ready}
        })

      [_before, active_row] = String.split(html, ~s(phx-value-id="2"))

      refute active_row |> String.slice(0, 300) =~
               ~s(class="flex w-full items-start gap-2.5 rounded-xl px-3 py-2.5 text-left transition #{@backdrop}"),
             "the highlight must differ from the panel it sits on"

      assert html =~ "bg-primary/10"
    end

    test "the hover tint is not the backdrop colour either" do
      results = [%{id: "1", label: "A"}]

      html =
        card(%{
          status: "ok",
          results: results,
          active: -1,
          snapshot: %{enabled?: true, status: :ready}
        })

      refute html =~ "hover:bg-base-200"
      assert html =~ "hover:bg-base-100"
    end
  end

  describe "before anything has been searched" do
    test "stays quiet even when the service is missing" do
      html = card(%{query: "", results: [], status: "ok", snapshot: nil, searched: false})

      refute html =~ "not installed"
      refute html =~ "No results"
    end
  end
end
