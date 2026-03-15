module NewsGeocodable
  extend ActiveSupport::Concern

  # City name -> [lat, lng] for city-level geocoding (population 500k+ / strategic importance)
  # Checked BEFORE country-level resolution for precise placement
  CITY_COORDS = {
    # --- United States ---
    "new york" => [40.71, -74.01], "los angeles" => [34.05, -118.24],
    "chicago" => [41.88, -87.63], "houston" => [29.76, -95.37],
    "phoenix" => [33.45, -112.07], "philadelphia" => [39.95, -75.17],
    "san antonio" => [29.42, -98.49], "san diego" => [32.72, -117.16],
    "dallas" => [32.78, -96.80], "san jose" => [37.34, -121.89],
    "austin" => [30.27, -97.74], "jacksonville" => [30.33, -81.66],
    "san francisco" => [37.77, -122.42], "columbus" => [39.96, -82.99],
    "indianapolis" => [39.77, -86.16], "charlotte" => [35.23, -80.84],
    "seattle" => [47.61, -122.33], "denver" => [39.74, -104.99],
    "washington" => [38.91, -77.04], "nashville" => [36.16, -86.78],
    "oklahoma city" => [35.47, -97.52], "el paso" => [31.76, -106.45],
    "boston" => [42.36, -71.06], "portland" => [45.52, -122.68],
    "las vegas" => [36.17, -115.14], "memphis" => [35.15, -90.05],
    "louisville" => [38.25, -85.76], "baltimore" => [39.29, -76.61],
    "milwaukee" => [43.04, -87.91], "albuquerque" => [35.08, -106.65],
    "tucson" => [32.22, -110.97], "fresno" => [36.74, -119.77],
    "sacramento" => [38.58, -121.49], "mesa" => [33.42, -111.83],
    "kansas city" => [39.10, -94.58], "atlanta" => [33.75, -84.39],
    "omaha" => [41.26, -95.94], "colorado springs" => [38.83, -104.82],
    "raleigh" => [35.78, -78.64], "miami" => [25.76, -80.19],
    "minneapolis" => [44.98, -93.27], "cleveland" => [41.50, -81.69],
    "tampa" => [27.95, -82.46], "new orleans" => [29.95, -90.07],
    "pittsburgh" => [40.44, -79.99], "cincinnati" => [39.10, -84.51],
    "st. louis" => [38.63, -90.20], "st louis" => [38.63, -90.20],
    "detroit" => [42.33, -83.05], "honolulu" => [21.31, -157.86],
    "silicon valley" => [37.39, -122.03], "anchorage" => [61.22, -149.90],
    "orlando" => [28.54, -81.38], "salt lake city" => [40.76, -111.89],
    "richmond" => [37.54, -77.44], "buffalo" => [42.89, -78.88],

    # --- Canada ---
    "toronto" => [43.65, -79.38], "montreal" => [45.50, -73.57],
    "vancouver" => [49.28, -123.12], "calgary" => [51.05, -114.07],
    "edmonton" => [53.55, -113.49], "ottawa" => [45.42, -75.70],
    "winnipeg" => [49.90, -97.14], "quebec city" => [46.81, -71.21],
    "halifax" => [44.65, -63.57],

    # --- Mexico & Central America ---
    "mexico city" => [19.43, -99.13], "guadalajara" => [20.67, -103.35],
    "monterrey" => [25.67, -100.31], "puebla" => [19.04, -98.20],
    "tijuana" => [32.51, -117.04], "cancun" => [21.16, -86.85],
    "panama city" => [8.98, -79.52], "san salvador" => [13.69, -89.22],
    "guatemala city" => [14.63, -90.51], "tegucigalpa" => [14.07, -87.19],
    "managua" => [12.11, -86.27], "san jose cr" => [9.93, -84.08],
    "havana" => [23.11, -82.37],

    # --- South America ---
    "são paulo" => [-23.55, -46.63], "sao paulo" => [-23.55, -46.63],
    "rio de janeiro" => [-22.91, -43.17], "buenos aires" => [-34.60, -58.38],
    "bogotá" => [4.71, -74.07], "bogota" => [4.71, -74.07],
    "lima" => [-12.05, -77.04], "santiago" => [-33.45, -70.67],
    "caracas" => [10.48, -66.90], "quito" => [-0.18, -78.47],
    "medellín" => [6.25, -75.56], "medellin" => [6.25, -75.56],
    "cali" => [3.45, -76.53], "brasília" => [-15.79, -47.88],
    "brasilia" => [-15.79, -47.88], "montevideo" => [-34.91, -56.19],
    "asunción" => [-25.26, -57.58], "asuncion" => [-25.26, -57.58],
    "la paz" => [-16.50, -68.15], "guayaquil" => [-2.17, -79.92],
    "recife" => [-8.05, -34.87], "salvador" => [-12.97, -38.51],
    "fortaleza" => [-3.72, -38.52], "belo horizonte" => [-19.92, -43.94],
    "porto alegre" => [-30.03, -51.23], "curitiba" => [-25.43, -49.27],
    "barranquilla" => [10.96, -74.78], "cartagena" => [10.39, -75.51],
    "maracaibo" => [10.63, -71.63],

    # --- Europe: UK & Ireland ---
    "london" => [51.51, -0.13], "manchester" => [53.48, -2.24],
    "birmingham" => [52.49, -1.89], "leeds" => [53.80, -1.55],
    "glasgow" => [55.86, -4.25], "liverpool" => [53.41, -2.98],
    "edinburgh" => [55.95, -3.19], "bristol" => [51.45, -2.59],
    "cardiff" => [51.48, -3.18], "belfast" => [54.60, -5.93],
    "dublin" => [53.35, -6.26], "cork" => [51.90, -8.47],

    # --- Europe: Western ---
    "paris" => [48.86, 2.35], "marseille" => [43.30, 5.37],
    "lyon" => [45.76, 4.84], "toulouse" => [43.60, 1.44],
    "nice" => [43.71, 7.26], "strasbourg" => [48.57, 7.75],
    "berlin" => [52.52, 13.41], "hamburg" => [53.55, 9.99],
    "munich" => [48.14, 11.58], "cologne" => [50.94, 6.96],
    "frankfurt" => [50.11, 8.68], "stuttgart" => [48.78, 9.18],
    "düsseldorf" => [51.23, 6.78], "dusseldorf" => [51.23, 6.78],
    "amsterdam" => [52.37, 4.90], "rotterdam" => [51.92, 4.48],
    "the hague" => [52.07, 4.30], "brussels" => [50.85, 4.35],
    "antwerp" => [51.22, 4.40], "zurich" => [47.38, 8.54],
    "geneva" => [46.20, 6.14], "bern" => [46.95, 7.45],
    "vienna" => [48.21, 16.37], "rome" => [41.90, 12.50],
    "milan" => [45.46, 9.19], "naples" => [40.85, 14.27],
    "turin" => [45.07, 7.69], "madrid" => [40.42, -3.70],
    "barcelona" => [41.39, 2.17], "valencia" => [39.47, -0.38],
    "seville" => [37.39, -5.98], "lisbon" => [38.72, -9.14],
    "porto" => [41.15, -8.61], "luxembourg" => [49.61, 6.13],

    # --- Europe: Nordic ---
    "stockholm" => [59.33, 18.07], "gothenburg" => [57.71, 11.97],
    "oslo" => [59.91, 10.75], "copenhagen" => [55.68, 12.57],
    "helsinki" => [60.17, 24.94], "reykjavik" => [64.15, -21.94],

    # --- Europe: Eastern ---
    "warsaw" => [52.23, 21.01], "krakow" => [50.06, 19.94],
    "prague" => [50.08, 14.44], "budapest" => [47.50, 19.04],
    "bucharest" => [44.43, 26.10], "sofia" => [42.70, 23.32],
    "athens" => [37.98, 23.73], "thessaloniki" => [40.64, 22.94],
    "zagreb" => [45.81, 15.98], "belgrade" => [44.82, 20.46],
    "sarajevo" => [43.86, 18.41], "skopje" => [41.99, 21.43],
    "tirana" => [41.33, 19.82], "podgorica" => [42.44, 19.26],
    "ljubljana" => [46.05, 14.51], "bratislava" => [48.15, 17.11],
    "vilnius" => [54.69, 25.28], "riga" => [56.95, 24.11],
    "tallinn" => [59.44, 24.75], "minsk" => [53.90, 27.57],
    "chisinau" => [47.01, 28.86],

    # --- Russia & Ukraine (conflict zones) ---
    "moscow" => [55.76, 37.62], "st. petersburg" => [59.93, 30.32],
    "st petersburg" => [59.93, 30.32], "saint petersburg" => [59.93, 30.32],
    "novosibirsk" => [55.04, 82.93], "yekaterinburg" => [56.84, 60.60],
    "kazan" => [55.80, 49.11], "nizhny novgorod" => [56.30, 44.00],
    "chelyabinsk" => [55.16, 61.40], "samara" => [53.20, 50.15],
    "rostov-on-don" => [47.24, 39.71], "rostov" => [47.24, 39.71],
    "volgograd" => [48.71, 44.51], "sochi" => [43.60, 39.73],
    "vladivostok" => [43.12, 131.87], "krasnoyarsk" => [56.01, 92.87],
    "kyiv" => [50.45, 30.52], "kiev" => [50.45, 30.52],
    "kharkiv" => [49.99, 36.23], "odesa" => [46.48, 30.73],
    "odessa" => [46.48, 30.73], "dnipro" => [48.46, 35.05],
    "donetsk" => [48.00, 37.80], "luhansk" => [48.57, 39.31],
    "zaporizhzhia" => [47.84, 35.14], "mariupol" => [47.10, 37.55],
    "kherson" => [46.64, 32.62], "lviv" => [49.84, 24.03],
    "kramatorsk" => [48.74, 37.56], "bakhmut" => [48.60, 38.00],
    "melitopol" => [46.84, 35.37], "sevastopol" => [44.62, 33.52],
    "crimea" => [44.95, 34.10], "simferopol" => [44.95, 34.10],

    # --- Middle East ---
    "tehran" => [35.69, 51.39], "isfahan" => [32.65, 51.68],
    "tabriz" => [38.08, 46.29], "mashhad" => [36.30, 59.60],
    "baghdad" => [33.31, 44.37], "basra" => [30.51, 47.81],
    "mosul" => [36.34, 43.14], "erbil" => [36.19, 44.01],
    "kirkuk" => [35.47, 44.39],
    "riyadh" => [24.71, 46.68], "jeddah" => [21.49, 39.19],
    "mecca" => [21.43, 39.83], "medina" => [24.47, 39.61],
    "dubai" => [25.20, 55.27], "abu dhabi" => [24.45, 54.65],
    "doha" => [25.29, 51.53], "kuwait city" => [29.38, 47.99],
    "manama" => [26.23, 50.59], "muscat" => [23.59, 58.54],
    "amman" => [31.95, 35.93], "beirut" => [33.89, 35.50],
    "tripoli" => [32.90, 13.18],
    "damascus" => [33.51, 36.29], "aleppo" => [36.20, 37.13],
    "homs" => [34.73, 36.71], "idlib" => [35.93, 36.63],
    "jerusalem" => [31.77, 35.23], "tel aviv" => [32.09, 34.78],
    "haifa" => [32.79, 34.99], "gaza" => [31.50, 34.47],
    "gaza city" => [31.50, 34.47], "west bank" => [31.95, 35.30],
    "ramallah" => [31.90, 35.20], "rafah" => [31.30, 34.25],
    "khan younis" => [31.35, 34.30], "nablus" => [32.22, 35.26],
    "sana'a" => [15.35, 44.21], "sanaa" => [15.35, 44.21],
    "aden" => [12.79, 45.04],
    "istanbul" => [41.01, 28.98], "ankara" => [39.93, 32.86],
    "izmir" => [38.42, 27.13], "antalya" => [36.90, 30.70],

    # --- South & Central Asia ---
    "kabul" => [34.53, 69.17], "kandahar" => [31.61, 65.71],
    "islamabad" => [33.69, 73.04], "karachi" => [24.86, 67.01],
    "lahore" => [31.55, 74.35], "peshawar" => [34.01, 71.58],
    "rawalpindi" => [33.60, 73.05],
    "mumbai" => [19.08, 72.88], "delhi" => [28.61, 77.21],
    "new delhi" => [28.61, 77.21], "bangalore" => [12.97, 77.59],
    "bengaluru" => [12.97, 77.59], "hyderabad" => [17.39, 78.49],
    "chennai" => [13.08, 80.27], "kolkata" => [22.57, 88.36],
    "ahmedabad" => [23.02, 72.57], "pune" => [18.52, 73.86],
    "jaipur" => [26.91, 75.79], "lucknow" => [26.85, 80.95],
    "surat" => [21.17, 72.83], "kanpur" => [26.45, 80.35],
    "dhaka" => [23.81, 90.41], "chittagong" => [22.36, 91.78],
    "colombo" => [6.93, 79.84], "kathmandu" => [27.72, 85.32],

    # --- East Asia ---
    "beijing" => [39.90, 116.40], "shanghai" => [31.23, 121.47],
    "guangzhou" => [23.13, 113.26], "shenzhen" => [22.54, 114.06],
    "chengdu" => [30.57, 104.07], "wuhan" => [30.59, 114.31],
    "hangzhou" => [30.27, 120.15], "nanjing" => [32.06, 118.80],
    "xi'an" => [34.26, 108.94], "xian" => [34.26, 108.94],
    "chongqing" => [29.56, 106.55], "tianjin" => [39.14, 117.18],
    "hong kong" => [22.32, 114.17], "macau" => [22.20, 113.55],
    "lhasa" => [29.65, 91.10], "urumqi" => [43.83, 87.62],
    "tokyo" => [35.68, 139.69], "osaka" => [34.69, 135.50],
    "yokohama" => [35.44, 139.64], "nagoya" => [35.18, 136.91],
    "sapporo" => [43.06, 141.35], "fukuoka" => [33.59, 130.40],
    "kyoto" => [35.01, 135.77], "kobe" => [34.69, 135.20],
    "hiroshima" => [34.40, 132.46],
    "seoul" => [37.57, 126.98], "busan" => [35.18, 129.08],
    "incheon" => [37.46, 126.71], "pyongyang" => [39.04, 125.76],
    "taipei" => [25.03, 121.57], "kaohsiung" => [22.63, 120.30],
    "ulaanbaatar" => [47.91, 106.91],

    # --- Southeast Asia ---
    "bangkok" => [13.76, 100.50], "ho chi minh city" => [10.82, 106.63],
    "hanoi" => [21.03, 105.85], "manila" => [14.60, 120.98],
    "jakarta" => [-6.21, 106.85], "surabaya" => [-7.25, 112.75],
    "kuala lumpur" => [3.14, 101.69], "singapore" => [1.35, 103.82],
    "yangon" => [16.87, 96.20], "naypyidaw" => [19.76, 96.07],
    "phnom penh" => [11.56, 104.93], "vientiane" => [17.97, 102.63],
    "bandar seri begawan" => [4.94, 114.95],

    # --- Africa ---
    "cairo" => [30.04, 31.24], "alexandria" => [31.20, 29.92],
    "lagos" => [6.52, 3.38], "abuja" => [9.06, 7.49],
    "nairobi" => [-1.29, 36.82], "mombasa" => [-4.05, 39.67],
    "johannesburg" => [-26.20, 28.04], "cape town" => [-33.93, 18.42],
    "durban" => [-29.86, 31.02], "pretoria" => [-25.75, 28.19],
    "addis ababa" => [9.02, 38.75], "dar es salaam" => [-6.79, 39.28],
    "kinshasa" => [-4.44, 15.27], "luanda" => [-8.84, 13.23],
    "accra" => [5.56, -0.19], "dakar" => [14.69, -17.44],
    "kampala" => [0.35, 32.58], "maputo" => [-25.97, 32.57],
    "lusaka" => [-15.39, 28.32], "harare" => [-17.83, 31.05],
    "algiers" => [36.75, 3.04], "tunis" => [36.81, 10.18],
    "casablanca" => [33.57, -7.59], "rabat" => [34.01, -6.84],
    "khartoum" => [15.50, 32.56], "mogadishu" => [2.05, 45.32],
    "abidjan" => [5.32, -4.01], "bamako" => [12.64, -8.00],
    "ouagadougou" => [12.37, -1.52], "niamey" => [13.51, 2.13],
    "conakry" => [9.64, -13.58], "freetown" => [8.48, -13.23],
    "monrovia" => [6.30, -10.80],
    "benghazi" => [32.12, 20.09], "misrata" => [32.38, 15.09],
    "port sudan" => [19.62, 37.22], "el fasher" => [13.63, 25.35],
    "n'djamena" => [12.13, 15.05], "ndjamena" => [12.13, 15.05],
    "bangui" => [4.37, 18.52], "juba" => [4.85, 31.58],
    "asmara" => [15.34, 38.93], "djibouti" => [11.59, 43.15],
    "antananarivo" => [-18.91, 47.52], "windhoek" => [-22.56, 17.08],
    "gaborone" => [-24.65, 25.91], "lilongwe" => [-13.96, 33.79],

    # --- Oceania ---
    "sydney" => [-33.87, 151.21], "melbourne" => [-37.81, 144.96],
    "brisbane" => [-27.47, 153.03], "perth" => [-31.95, 115.86],
    "adelaide" => [-34.93, 138.60], "canberra" => [-35.28, 149.13],
    "gold coast" => [-28.00, 153.43], "hobart" => [-42.88, 147.33],
    "darwin" => [-12.46, 130.84], "auckland" => [-36.85, 174.76],
    "wellington" => [-41.29, 174.78], "christchurch" => [-43.53, 172.64],

    # --- Caribbean ---
    "kingston" => [18.00, -76.79], "port-au-prince" => [18.54, -72.34],
    "santo domingo" => [18.49, -69.93], "san juan" => [18.47, -66.11],
    "nassau" => [25.05, -77.34],
  }.freeze

  # Pre-sorted by name length descending for longest-match-first
  CITY_PATTERNS = CITY_COORDS.keys.sort_by { |k| -k.length }.freeze

  # Regex cache for word-boundary matching on city names
  CITY_REGEXES = CITY_PATTERNS.each_with_object({}) do |city, h|
    h[city] = /\b#{Regexp.escape(city)}\b/i
  end.freeze

  # Country code -> [lat, lng] for geocoding APIs that only return country
  COUNTRY_COORDS = {
    "us" => [38.9, -77.0], "gb" => [51.5, -0.1], "uk" => [51.5, -0.1],
    "fr" => [48.9, 2.3], "de" => [52.5, 13.4], "it" => [41.9, 12.5],
    "es" => [40.4, -3.7], "pt" => [38.7, -9.1], "nl" => [52.4, 4.9],
    "be" => [50.8, 4.4], "ch" => [46.9, 7.4], "at" => [48.2, 16.4],
    "se" => [59.3, 18.1], "no" => [59.9, 10.8], "dk" => [55.7, 12.6],
    "fi" => [60.2, 24.9], "pl" => [52.2, 21.0], "cz" => [50.1, 14.4],
    "hu" => [47.5, 19.0], "ro" => [44.4, 26.1], "bg" => [42.7, 23.3],
    "gr" => [37.98, 23.7], "hr" => [45.8, 16.0], "rs" => [44.8, 20.5],
    "ua" => [50.4, 30.5], "ru" => [55.8, 37.6], "tr" => [39.9, 32.9],
    "il" => [31.8, 35.2], "ae" => [25.3, 55.3], "sa" => [24.7, 46.7],
    "qa" => [25.3, 51.5], "kw" => [29.4, 47.98], "ir" => [35.7, 51.4],
    "iq" => [33.3, 44.4], "jo" => [31.95, 35.9], "lb" => [33.9, 35.5],
    "eg" => [30.0, 31.2], "za" => [-33.9, 18.4], "ng" => [9.1, 7.5],
    "ke" => [-1.3, 36.8], "et" => [9.0, 38.7], "gh" => [5.6, -0.2],
    "ma" => [34.0, -6.8], "tn" => [36.8, 10.2], "dz" => [36.8, 3.1],
    "cn" => [39.9, 116.4], "jp" => [35.7, 139.7], "kr" => [37.6, 127.0],
    "in" => [28.6, 77.2], "pk" => [33.7, 73.0], "bd" => [23.8, 90.4],
    "th" => [13.75, 100.5], "vn" => [21.0, 105.85], "ph" => [14.6, 121.0],
    "id" => [-6.2, 106.8], "my" => [3.1, 101.7], "sg" => [1.35, 103.8],
    "au" => [-33.9, 151.2], "nz" => [-41.3, 174.8],
    "ca" => [45.4, -75.7], "mx" => [19.4, -99.1], "br" => [-15.8, -47.9],
    "ar" => [-34.6, -58.4], "cl" => [-33.4, -70.6], "co" => [4.7, -74.1],
    "pe" => [-12.0, -77.0], "ve" => [10.5, -66.9],
    "ie" => [53.3, -6.3], "sk" => [48.1, 17.1], "si" => [46.05, 14.5],
    "lt" => [54.7, 25.3], "lv" => [56.95, 24.1], "ee" => [59.4, 24.7],
    "tw" => [25.0, 121.5], "hk" => [22.3, 114.2], "ly" => [32.9, 13.2],
    "sd" => [15.6, 32.5], "ug" => [0.3, 32.6], "tz" => [-6.8, 39.3],
    "mm" => [19.75, 96.1], "af" => [34.5, 69.2], "sy" => [33.5, 36.3],
    "ye" => [15.4, 44.2], "cu" => [23.1, -82.4], "ec" => [-0.2, -78.5],
  }.freeze

  # Full country name -> code mapping
  COUNTRY_NAME_MAP = {
    "united states" => "us", "united kingdom" => "gb", "france" => "fr",
    "germany" => "de", "italy" => "it", "spain" => "es", "canada" => "ca",
    "australia" => "au", "india" => "in", "china" => "cn", "japan" => "jp",
    "south korea" => "kr", "brazil" => "br", "mexico" => "mx", "russia" => "ru",
    "turkey" => "tr", "israel" => "il", "ukraine" => "ua", "poland" => "pl",
    "netherlands" => "nl", "belgium" => "be", "switzerland" => "ch",
    "austria" => "at", "sweden" => "se", "norway" => "no", "denmark" => "dk",
    "finland" => "fi", "ireland" => "ie", "portugal" => "pt", "greece" => "gr",
    "romania" => "ro", "hungary" => "hu", "czech republic" => "cz",
    "egypt" => "eg", "south africa" => "za", "nigeria" => "ng",
    "saudi arabia" => "sa", "iran" => "ir", "iraq" => "iq",
    "united arab emirates" => "ae", "pakistan" => "pk", "indonesia" => "id",
    "thailand" => "th", "vietnam" => "vn", "philippines" => "ph",
    "malaysia" => "my", "singapore" => "sg", "new zealand" => "nz",
    "argentina" => "ar", "colombia" => "co", "chile" => "cl", "peru" => "pe",
    "taiwan" => "tw", "hong kong" => "hk", "syria" => "sy", "yemen" => "ye",
    "afghanistan" => "af", "myanmar" => "mm", "libya" => "ly", "sudan" => "sd",
    "cuba" => "cu", "ecuador" => "ec", "venezuela" => "ve",
  }.freeze

  # Words that map to countries (for title-based geocoding)
  TITLE_GEO_MAP = COUNTRY_NAME_MAP.merge(
    # Government/institutions
    "pentagon" => "us", "white house" => "us",
    "congress" => "us", "senate" => "us", "fcc" => "us", "fbi" => "us",
    "cia" => "us", "nsa" => "us", "doj" => "us",
    "kremlin" => "ru",
    "nato" => "be", "eu" => "be", "european union" => "be",
    # Australian states/regions
    "queensland" => "au", "victoria" => "au", "tasmania" => "au",
    "new south wales" => "au", "western australia" => "au",
    # Companies as proxy
    "google" => "us", "apple" => "us", "microsoft" => "us", "amazon" => "us",
    "meta" => "us", "openai" => "us", "anthropic" => "us", "nvidia" => "us",
    "tesla" => "us", "spacex" => "us",
  ).freeze

  TITLE_GEO_PATTERNS = TITLE_GEO_MAP.keys.sort_by { |k| -k.length }.freeze

  # ccTLD -> country code (covers common two-part TLDs like .co.nz, .com.au)
  DOMAIN_TLD_MAP = {
    "au" => "au", "nz" => "nz", "uk" => "gb", "ie" => "ie",
    "fr" => "fr", "de" => "de", "it" => "it", "es" => "es",
    "pt" => "pt", "nl" => "nl", "be" => "be", "ch" => "ch",
    "at" => "at", "se" => "se", "no" => "no", "dk" => "dk",
    "fi" => "fi", "pl" => "pl", "cz" => "cz", "hu" => "hu",
    "ro" => "ro", "bg" => "bg", "gr" => "gr", "hr" => "hr",
    "rs" => "rs", "ua" => "ua", "ru" => "ru", "tr" => "tr",
    "il" => "il", "ae" => "ae", "sa" => "sa", "qa" => "qa",
    "ir" => "ir", "iq" => "iq", "eg" => "eg", "za" => "za",
    "ng" => "ng", "ke" => "ke", "ug" => "ug", "gh" => "gh",
    "ma" => "ma", "tn" => "tn", "cn" => "cn", "jp" => "jp",
    "kr" => "kr", "in" => "in", "pk" => "pk", "bd" => "bd",
    "th" => "th", "vn" => "vn", "ph" => "ph", "id" => "id",
    "my" => "my", "sg" => "sg", "tw" => "tw", "hk" => "hk",
    "ca" => "ca", "mx" => "mx", "br" => "br", "ar" => "ar",
    "cl" => "cl", "co" => "co", "pe" => "pe",
    "md" => "ro",
  }.freeze

  # Well-known domains with no ccTLD that map to a specific country
  DOMAIN_PUBLISHER_MAP = {
    "foxnews.com" => "us", "nypost.com" => "us", "tmz.com" => "us",
    "yahoo.com" => "us", "foxbusiness.com" => "us", "wtop.com" => "us",
    "prnewswire.com" => "us", "phys.org" => "us", "fool.com" => "us",
    "seekingalpha.com" => "us", "marketbeat.com" => "us",
    "tickerreport.com" => "us", "sportskeeda.com" => "in",
    "jpost.com" => "il", "straitstimes.com" => "sg",
    "independent.co.uk" => "gb", "mirror.co.uk" => "gb",
  }.freeze

  private

  # Resolution order:
  # 1. City match from title (most specific)
  # 2. Country code lookup
  # 3. Country name lookup
  # 4. Country/keyword from title patterns
  # 5. Domain TLD/publisher
  def resolve_location(country_hint, title, url = nil)
    lat, lng = geocode_city_from_title(title) ||
               geocode_country(country_hint) ||
               geocode_country_name(country_hint) ||
               geocode_from_title(title) ||
               geocode_from_domain(url)
    return nil unless lat && lng

    # Small jitter so same-location articles don't stack exactly
    [lat + rand(-0.15..0.15), lng + rand(-0.15..0.15)]
  end

  # Word-boundary city matching against title, longest match first
  def geocode_city_from_title(title)
    return nil if title.blank?
    CITY_PATTERNS.each do |city|
      return CITY_COORDS[city] if CITY_REGEXES[city].match?(title)
    end
    nil
  end

  def geocode_country(code)
    return nil if code.blank?
    COUNTRY_COORDS[code.to_s.downcase.strip]
  end

  def geocode_country_name(name)
    return nil if name.blank?
    lower = name.to_s.downcase.strip
    code = COUNTRY_NAME_MAP[lower]
    return COUNTRY_COORDS[code] if code
    # Partial match
    COUNTRY_NAME_MAP.each { |n, c| return COUNTRY_COORDS[c] if lower.include?(n) }
    nil
  end

  def geocode_from_title(title)
    return nil if title.blank?
    lower = title.downcase
    TITLE_GEO_PATTERNS.each do |pattern|
      if lower.include?(pattern)
        code = TITLE_GEO_MAP[pattern]
        return COUNTRY_COORDS[code] if code
      end
    end
    nil
  end

  def geocode_from_domain(url)
    return nil if url.blank?
    host = URI.parse(url).host&.downcase&.sub(/^www\./, "")
    return nil if host.blank?

    # Check known publisher domains first
    code = DOMAIN_PUBLISHER_MAP[host]
    return COUNTRY_COORDS[code] if code

    # Extract ccTLD: handle .com.au, .co.nz, .net.au, etc.
    parts = host.split(".")
    tld = parts.last
    # Skip generic TLDs
    return nil if %w[com org net io edu gov].include?(tld)

    code = DOMAIN_TLD_MAP[tld]
    return COUNTRY_COORDS[code] if code

    nil
  rescue URI::InvalidURIError
    nil
  end
end
