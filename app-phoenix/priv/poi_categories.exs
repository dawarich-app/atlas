[
  %{
    id: "food",
    label: "Food & Drink",
    icon: "utensils",
    items: [
      %{id: "restaurant", label: "Restaurant", selector: "amenity=restaurant", icon: "utensils", pinned: true},
      %{id: "cafe", label: "Café", selector: "amenity=cafe", icon: "coffee", pinned: true},
      %{id: "bar", label: "Bar", selector: "amenity=bar", icon: "wine", pinned: true},
      %{id: "pub", label: "Pub", selector: "amenity=pub", icon: "beer", pinned: false},
      %{id: "fast_food", label: "Fast food", selector: "amenity=fast_food", icon: "pizza", pinned: true},
      %{id: "ice_cream", label: "Ice cream", selector: "amenity=ice_cream", icon: "ice-cream-cone", pinned: false},
      %{id: "biergarten", label: "Beer garden", selector: "amenity=biergarten", icon: "beer", pinned: false},
      %{id: "food_court", label: "Food court", selector: "amenity=food_court", icon: "utensils", pinned: false},
      %{id: "bakery", label: "Bakery", selector: "shop=bakery", icon: "croissant", pinned: false},
      %{id: "butcher", label: "Butcher", selector: "shop=butcher", icon: "drumstick", pinned: false},
      %{id: "deli", label: "Deli", selector: "shop=deli", icon: "utensils", pinned: false},
      %{id: "drinking_water", label: "Drinking water", selector: "amenity=drinking_water", icon: "droplet", pinned: false}
    ]
  },
  %{
    id: "shopping",
    label: "Shopping",
    icon: "shopping-bag",
    items: [
      %{id: "supermarket", label: "Supermarket", selector: "shop=supermarket", icon: "shopping-cart", pinned: true},
      %{id: "convenience", label: "Convenience", selector: "shop=convenience", icon: "shopping-cart", pinned: false},
      %{id: "mall", label: "Mall", selector: "shop=mall", icon: "shopping-bag", pinned: false},
      %{id: "marketplace", label: "Marketplace", selector: "amenity=marketplace", icon: "store", pinned: false},
      %{id: "clothes", label: "Clothing", selector: "shop=clothes", icon: "shirt", pinned: false},
      %{id: "shoes", label: "Shoes", selector: "shop=shoes", icon: "footprints", pinned: false},
      %{id: "electronics", label: "Electronics", selector: "shop=electronics", icon: "cpu", pinned: false},
      %{id: "mobile_phone", label: "Mobile phones", selector: "shop=mobile_phone", icon: "smartphone", pinned: false},
      %{id: "books", label: "Books", selector: "shop=books", icon: "book", pinned: false},
      %{id: "gift", label: "Gifts", selector: "shop=gift", icon: "gift", pinned: false},
      %{id: "florist", label: "Florist", selector: "shop=florist", icon: "flower", pinned: false},
      %{id: "jewelry", label: "Jewelry", selector: "shop=jewelry", icon: "gem", pinned: false},
      %{id: "optician", label: "Optician", selector: "shop=optician", icon: "glasses", pinned: false},
      %{id: "hairdresser", label: "Hairdresser", selector: "shop=hairdresser", icon: "scissors", pinned: false},
      %{id: "beauty", label: "Beauty", selector: "shop=beauty", icon: "sparkles", pinned: false},
      %{id: "laundry", label: "Laundry", selector: "shop=laundry", icon: "shirt", pinned: false},
      %{id: "hardware", label: "Hardware", selector: "shop=hardware", icon: "hammer", pinned: false},
      %{id: "bookmaker", label: "Bookmaker", selector: "shop=bookmaker", icon: "dice-5", pinned: false},
      %{id: "pet", label: "Pet supplies", selector: "shop=pet", icon: "dog", pinned: false},
      %{id: "toys", label: "Toys", selector: "shop=toys", icon: "gamepad-2", pinned: false},
      %{id: "sports_shop", label: "Sporting goods", selector: "shop=sports", icon: "trophy", pinned: false}
    ]
  },
  %{
    id: "transport",
    label: "Transport",
    icon: "bus",
    items: [
      %{id: "fuel", label: "Fuel", selector: "amenity=fuel", icon: "fuel", pinned: true},
      %{id: "parking", label: "Parking", selector: "amenity=parking", icon: "circle-parking", pinned: true},
      %{id: "charging_station", label: "EV charging", selector: "amenity=charging_station", icon: "zap", pinned: true},
      %{id: "bicycle_rental", label: "Bike rental", selector: "amenity=bicycle_rental", icon: "bike", pinned: false},
      %{id: "bicycle_parking", label: "Bike parking", selector: "amenity=bicycle_parking", icon: "bike", pinned: false},
      %{id: "car_rental", label: "Car rental", selector: "amenity=car_rental", icon: "car", pinned: false},
      %{id: "car_sharing", label: "Car sharing", selector: "amenity=car_sharing", icon: "car", pinned: false},
      %{id: "taxi", label: "Taxi", selector: "amenity=taxi", icon: "car", pinned: false},
      %{id: "bus_stop", label: "Bus stop", selector: "highway=bus_stop", icon: "bus", pinned: false},
      %{id: "subway", label: "Subway", selector: "railway=subway_entrance", icon: "train-front-tunnel", pinned: false},
      %{id: "tram_stop", label: "Tram stop", selector: "railway=tram_stop", icon: "train-track", pinned: false},
      %{id: "train_station", label: "Train station", selector: "railway=station", icon: "train-front", pinned: false},
      %{id: "ferry_terminal", label: "Ferry terminal", selector: "amenity=ferry_terminal", icon: "ship", pinned: false},
      %{id: "airport", label: "Airport", selector: "aeroway=aerodrome", icon: "plane", pinned: false},
      %{id: "motorway_services", label: "Services", selector: "highway=services", icon: "fuel", pinned: false}
    ]
  },
  %{
    id: "lodging",
    label: "Lodging",
    icon: "bed",
    items: [
      %{id: "hotel", label: "Hotel", selector: "tourism=hotel", icon: "bed", pinned: true},
      %{id: "hostel", label: "Hostel", selector: "tourism=hostel", icon: "bed", pinned: false},
      %{id: "guest_house", label: "Guest house", selector: "tourism=guest_house", icon: "home", pinned: false},
      %{id: "motel", label: "Motel", selector: "tourism=motel", icon: "bed", pinned: false},
      %{id: "camp_site", label: "Campground", selector: "tourism=camp_site", icon: "tent", pinned: false},
      %{id: "apartment", label: "Apartment", selector: "tourism=apartment", icon: "building-2", pinned: false}
    ]
  },
  %{
    id: "health",
    label: "Health",
    icon: "cross",
    items: [
      %{id: "pharmacy", label: "Pharmacy", selector: "amenity=pharmacy", icon: "pill", pinned: true},
      %{id: "hospital", label: "Hospital", selector: "amenity=hospital", icon: "hospital", pinned: false},
      %{id: "clinic", label: "Clinic", selector: "amenity=clinic", icon: "stethoscope", pinned: false},
      %{id: "doctors", label: "Doctor", selector: "amenity=doctors", icon: "stethoscope", pinned: false},
      %{id: "dentist", label: "Dentist", selector: "amenity=dentist", icon: "smile", pinned: false},
      %{id: "veterinary", label: "Veterinary", selector: "amenity=veterinary", icon: "paw-print", pinned: false},
      %{id: "optometrist", label: "Optometrist", selector: "healthcare=optometrist", icon: "glasses", pinned: false}
    ]
  },
  %{
    id: "civic",
    label: "Civic & Services",
    icon: "landmark",
    items: [
      %{id: "bank", label: "Bank", selector: "amenity=bank", icon: "landmark", pinned: true},
      %{id: "atm", label: "ATM", selector: "amenity=atm", icon: "banknote", pinned: true},
      %{id: "post_office", label: "Post office", selector: "amenity=post_office", icon: "mailbox", pinned: false},
      %{id: "post_box", label: "Post box", selector: "amenity=post_box", icon: "mail", pinned: false},
      %{id: "library", label: "Library", selector: "amenity=library", icon: "book-open", pinned: false},
      %{id: "police", label: "Police", selector: "amenity=police", icon: "shield", pinned: false},
      %{id: "fire_station", label: "Fire station", selector: "amenity=fire_station", icon: "flame", pinned: false},
      %{id: "town_hall", label: "Town hall", selector: "amenity=townhall", icon: "landmark", pinned: false},
      %{id: "courthouse", label: "Courthouse", selector: "amenity=courthouse", icon: "scale", pinned: false},
      %{id: "embassy", label: "Embassy", selector: "office=diplomatic", icon: "building-2", pinned: false},
      %{id: "place_of_worship", label: "Worship", selector: "amenity=place_of_worship", icon: "church", pinned: false},
      %{id: "school", label: "School", selector: "amenity=school", icon: "graduation-cap", pinned: false},
      %{id: "university", label: "University", selector: "amenity=university", icon: "graduation-cap", pinned: false},
      %{id: "kindergarten", label: "Kindergarten", selector: "amenity=kindergarten", icon: "baby", pinned: false}
    ]
  },
  %{
    id: "culture",
    label: "Culture & Sights",
    icon: "camera",
    items: [
      %{id: "museum", label: "Museum", selector: "tourism=museum", icon: "landmark", pinned: false},
      %{id: "attraction", label: "Attraction", selector: "tourism=attraction", icon: "camera", pinned: true},
      %{id: "viewpoint", label: "Viewpoint", selector: "tourism=viewpoint", icon: "mountain", pinned: false},
      %{id: "gallery", label: "Art gallery", selector: "tourism=gallery", icon: "image", pinned: false},
      %{id: "theatre", label: "Theatre", selector: "amenity=theatre", icon: "drama", pinned: false},
      %{id: "cinema", label: "Cinema", selector: "amenity=cinema", icon: "clapperboard", pinned: false},
      %{id: "arts_centre", label: "Arts centre", selector: "amenity=arts_centre", icon: "palette", pinned: false},
      %{id: "monument", label: "Monument", selector: "historic=monument", icon: "castle", pinned: false},
      %{id: "memorial", label: "Memorial", selector: "historic=memorial", icon: "flag", pinned: false},
      %{id: "castle", label: "Castle", selector: "historic=castle", icon: "castle", pinned: false},
      %{id: "ruins", label: "Ruins", selector: "historic=ruins", icon: "castle", pinned: false},
      %{id: "archaeological", label: "Archaeology", selector: "historic=archaeological_site", icon: "pickaxe", pinned: false},
      %{id: "nightclub", label: "Nightclub", selector: "amenity=nightclub", icon: "music", pinned: false},
      %{id: "stadium", label: "Stadium", selector: "leisure=stadium", icon: "trophy", pinned: false}
    ]
  },
  %{
    id: "outdoors",
    label: "Outdoors & Sport",
    icon: "trees",
    items: [
      %{id: "park", label: "Park", selector: "leisure=park", icon: "trees", pinned: true},
      %{id: "playground", label: "Playground", selector: "leisure=playground", icon: "baby", pinned: false},
      %{id: "garden", label: "Garden", selector: "leisure=garden", icon: "flower", pinned: false},
      %{id: "dog_park", label: "Dog park", selector: "leisure=dog_park", icon: "paw-print", pinned: false},
      %{id: "swimming_pool", label: "Swimming pool", selector: "leisure=swimming_pool", icon: "waves", pinned: false},
      %{id: "fitness_centre", label: "Gym", selector: "leisure=fitness_centre", icon: "dumbbell", pinned: false},
      %{id: "sports_centre", label: "Sports centre", selector: "leisure=sports_centre", icon: "trophy", pinned: false},
      %{id: "pitch", label: "Sports pitch", selector: "leisure=pitch", icon: "trophy", pinned: false},
      %{id: "golf_course", label: "Golf", selector: "leisure=golf_course", icon: "flag", pinned: false},
      %{id: "peak", label: "Peak", selector: "natural=peak", icon: "mountain", pinned: false},
      %{id: "beach", label: "Beach", selector: "natural=beach", icon: "waves", pinned: false},
      %{id: "picnic_site", label: "Picnic site", selector: "tourism=picnic_site", icon: "tent", pinned: false},
      %{id: "campfire", label: "Campfire", selector: "leisure=firepit", icon: "flame", pinned: false}
    ]
  },
  %{
    id: "facilities",
    label: "Public Facilities",
    icon: "info",
    items: [
      %{id: "toilets", label: "Toilets", selector: "amenity=toilets", icon: "toilet", pinned: true},
      %{id: "bench", label: "Bench", selector: "amenity=bench", icon: "square", pinned: false},
      %{id: "recycling", label: "Recycling", selector: "amenity=recycling", icon: "recycle", pinned: false},
      %{id: "waste_basket", label: "Waste basket", selector: "amenity=waste_basket", icon: "trash-2", pinned: false},
      %{id: "shelter", label: "Shelter", selector: "amenity=shelter", icon: "home", pinned: false},
      %{id: "shower", label: "Shower", selector: "amenity=shower", icon: "droplets", pinned: false},
      %{id: "telephone", label: "Telephone", selector: "amenity=telephone", icon: "phone", pinned: false},
      %{id: "vending", label: "Vending", selector: "amenity=vending_machine", icon: "package", pinned: false},
      %{id: "defibrillator", label: "Defibrillator", selector: "emergency=defibrillator", icon: "heart-pulse", pinned: false},
      %{id: "clock", label: "Public clock", selector: "amenity=clock", icon: "clock", pinned: false}
    ]
  }
]
