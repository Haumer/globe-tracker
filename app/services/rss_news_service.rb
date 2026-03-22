require "rss"
require "net/http"

class RssNewsService
  extend Refreshable
  include TimelineRecorder
  include NewsDedupable
  include NewsGeocodable

  BATCH_COUNT = 4        # 4 batches × 5 min = each feed polled every 20 min
  BATCH_INTERVAL = 5     # minutes between batches

  refreshes model: NewsEvent, interval: BATCH_INTERVAL.minutes

  # ── Source Credibility System ────────────────────────────────
  # Tier 1: Wire services, government, international organizations
  # Tier 2: Major outlets with editorial standards
  # Tier 3: Specialty, think tanks, OSINT, defense
  # Tier 4: Aggregators, blogs, search-based
  #
  # Risk: low / medium / high (propaganda risk)
  SOURCES = {
    # ── TIER 1: Wire Services & Government ─────────────────────
    { url: "https://feeds.reuters.com/reuters/worldNews", name: "Reuters" } =>
      { tier: 1, risk: "low", region: "global" },
    { url: "https://feeds.reuters.com/reuters/topNews", name: "Reuters Top" } =>
      { tier: 1, risk: "low", region: "global" },
    { url: "https://rss.nytimes.com/services/xml/rss/nyt/World.xml", name: "NYT World" } =>
      { tier: 1, risk: "low", region: "us" },
    { url: "https://news.un.org/feed/subscribe/en/news/all/rss.xml", name: "UN News" } =>
      { tier: 1, risk: "low", region: "global" },
    { url: "https://feeds.content.dowjones.io/public/rss/RSSUSnews", name: "WSJ" } =>
      { tier: 1, risk: "low", region: "us" },
    { url: "https://www.tagesschau.de/xml/rss2/", name: "Tagesschau" } =>
      { tier: 1, risk: "low", region: "europe" },
    { url: "https://www.ansa.it/sito/notizie/topnews/topnews_rss.xml", name: "ANSA" } =>
      { tier: 1, risk: "low", region: "europe" },
    { url: "https://feeds.nos.nl/nosnieuwsalgemeen", name: "NOS Nieuws" } =>
      { tier: 1, risk: "low", region: "europe" },
    { url: "https://www.svt.se/nyheter/rss.xml", name: "SVT Nyheter" } =>
      { tier: 1, risk: "low", region: "europe" },
    { url: "https://www.iaea.org/feeds/topnews", name: "IAEA" } =>
      { tier: 1, risk: "low", region: "global" },
    { url: "https://www.who.int/rss-feeds/news-english.xml", name: "WHO" } =>
      { tier: 1, risk: "low", region: "global" },
    { url: "https://www.cisa.gov/cybersecurity-advisories/all.xml", name: "CISA" } =>
      { tier: 1, risk: "low", region: "us" },
    { url: "https://www.pbs.org/newshour/feeds/rss/headlines", name: "PBS NewsHour" } =>
      { tier: 1, risk: "low", region: "us" },

    # ── TIER 2: Major Outlets ──────────────────────────────────
    # Global
    { url: "https://feeds.bbci.co.uk/news/world/rss.xml", name: "BBC World" } =>
      { tier: 2, risk: "low", region: "global" },
    { url: "https://www.theguardian.com/world/rss", name: "Guardian World" } =>
      { tier: 2, risk: "low", region: "global" },
    { url: "https://rss.cnn.com/rss/edition_world.rss", name: "CNN World" } =>
      { tier: 2, risk: "low", region: "global" },
    { url: "https://feeds.washingtonpost.com/rss/world", name: "Washington Post" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://feeds.npr.org/1004/rss.xml", name: "NPR World" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://feeds.abcnews.com/abcnews/topstories", name: "ABC News" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://www.cbsnews.com/latest/rss/main", name: "CBS News" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://feeds.nbcnews.com/nbcnews/public/news", name: "NBC News" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://api.axios.com/feed/", name: "Axios" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://rss.politico.com/politics-news.xml", name: "Politico" } =>
      { tier: 2, risk: "low", region: "us" },

    # Europe
    { url: "https://www.france24.com/en/rss", name: "France 24" } =>
      { tier: 2, risk: "medium", affiliation: "France", region: "europe" },
    { url: "https://www.euronews.com/rss?format=xml", name: "EuroNews" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.lemonde.fr/en/rss/une.xml", name: "Le Monde" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://rss.dw.com/xml/rss-en-all", name: "DW News" } =>
      { tier: 2, risk: "medium", affiliation: "Germany", region: "europe" },
    { url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/portada", name: "El Pais" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.spiegel.de/schlagzeilen/tops/index.rss", name: "Der Spiegel" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://newsfeed.zeit.de/index", name: "Die Zeit" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.corriere.it/rss/homepage.xml", name: "Corriere della Sera" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.repubblica.it/rss/homepage/rss2.0.xml", name: "La Repubblica" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.dn.se/rss/", name: "Dagens Nyheter" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.svd.se/feed/articles.rss", name: "Svenska Dagbladet" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.hurriyet.com.tr/rss/anasayfa", name: "Hurriyet" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://tvn24.pl/swiat.xml", name: "TVN24" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.polsatnews.pl/rss/wszystkie.xml", name: "Polsat News" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.rp.pl/rss_main", name: "Rzeczpospolita" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.naftemporiki.gr/feed/", name: "Naftemporiki" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://feeds.bbci.co.uk/turkce/rss.xml", name: "BBC Turkce" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://rss.dw.com/xml/rss-tur-all", name: "DW Turkish" } =>
      { tier: 2, risk: "medium", affiliation: "Germany", region: "europe" },
    { url: "https://meduza.io/rss/all", name: "Meduza" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://novayagazeta.eu/feed/rss", name: "Novaya Gazeta" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.themoscowtimes.com/rss/news", name: "Moscow Times" } =>
      { tier: 2, risk: "low", region: "europe" },

    # Middle East
    { url: "https://www.aljazeera.com/xml/rss/all.xml", name: "Al Jazeera" } =>
      { tier: 2, risk: "medium", affiliation: "Qatar", region: "middle-east" },
    { url: "https://feeds.bbci.co.uk/news/world/middle_east/rss.xml", name: "BBC Middle East" } =>
      { tier: 2, risk: "low", region: "middle-east" },
    { url: "https://www.theguardian.com/world/middleeast/rss", name: "Guardian ME" } =>
      { tier: 2, risk: "low", region: "middle-east" },
    { url: "https://feeds.bbci.co.uk/persian/rss.xml", name: "BBC Persian" } =>
      { tier: 2, risk: "low", region: "middle-east" },
    { url: "https://www.omanobserver.om/rssFeed/1", name: "Oman Observer" } =>
      { tier: 2, risk: "medium", affiliation: "Oman", region: "middle-east" },
    { url: "https://www.middleeasteye.net/rss", name: "Middle East Eye" } =>
      { tier: 2, risk: "medium", affiliation: "Qatar-linked", region: "middle-east" },
    # Al-Ahram: RSS returns 404/403, covered via GDELT/Google News instead
    { url: "https://www.middleeastmonitor.com/feed/", name: "Middle East Monitor" } =>
      { tier: 2, risk: "medium", region: "middle-east" },
    { url: "https://www.france24.com/en/middle-east/rss", name: "France 24 ME" } =>
      { tier: 2, risk: "medium", affiliation: "France", region: "middle-east" },
    { url: "https://www.newarab.com/rss", name: "The New Arab" } =>
      { tier: 2, risk: "medium", affiliation: "Qatar-linked", region: "middle-east" },
    { url: "https://www.dailysabah.com/rss/world", name: "Daily Sabah" } =>
      { tier: 2, risk: "medium", affiliation: "Turkey", region: "middle-east" },
    # TRT World, Arab News, Gulf News, Khaleej Times: RSS feeds return 403/404, covered via Google News proxies
    { url: "https://english.aawsat.com/feed", name: "Asharq Al-Awsat" } =>
      { tier: 2, risk: "medium", affiliation: "Saudi", region: "middle-east" },
    # i24NEWS: returns HTML not RSS, covered via Google News proxy below

    # Africa
    { url: "https://feeds.bbci.co.uk/news/world/africa/rss.xml", name: "BBC Africa" } =>
      { tier: 2, risk: "low", region: "africa" },
    { url: "https://feeds.news24.com/articles/news24/TopStories/rss", name: "News24 SA" } =>
      { tier: 2, risk: "low", region: "africa" },
    { url: "https://www.africanews.com/feed/rss", name: "Africanews" } =>
      { tier: 2, risk: "low", region: "africa" },
    { url: "https://www.bbc.com/afrique/index.xml", name: "BBC Afrique" } =>
      { tier: 2, risk: "low", region: "africa" },
    { url: "https://www.premiumtimesng.com/feed", name: "Premium Times" } =>
      { tier: 2, risk: "low", region: "africa" },
    { url: "https://www.vanguardngr.com/feed/", name: "Vanguard Nigeria" } =>
      { tier: 2, risk: "low", region: "africa" },
    { url: "https://www.channelstv.com/feed/", name: "Channels TV" } =>
      { tier: 2, risk: "low", region: "africa" },
    { url: "https://www.thisdaylive.com/feed", name: "ThisDay" } =>
      { tier: 2, risk: "low", region: "africa" },

    # Asia-Pacific
    { url: "https://feeds.bbci.co.uk/news/world/asia/rss.xml", name: "BBC Asia" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://www.channelnewsasia.com/api/v1/rss-outbound-feed?_format=xml", name: "CNA Singapore" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://www.thehindu.com/news/national/feeder/default.rss", name: "The Hindu" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://indianexpress.com/section/india/feed/", name: "Indian Express" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://feeds.feedburner.com/ndtvnews-top-stories", name: "NDTV" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://vnexpress.net/rss/tin-moi-nhat.rss", name: "VnExpress" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://tuoitrenews.vn/rss", name: "Tuoi Tre News" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://www.yonhapnewstv.co.kr/browse/feed/", name: "Yonhap" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://www.chosun.com/arc/outboundfeeds/rss/?outputType=xml", name: "Chosun Ilbo" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://www.abc.net.au/news/feed/2942460/rss.xml", name: "ABC Australia" } =>
      { tier: 2, risk: "low", region: "oceania" },
    { url: "https://www.theguardian.com/australia-news/rss", name: "Guardian Australia" } =>
      { tier: 2, risk: "low", region: "oceania" },

    # Latin America
    { url: "https://feeds.bbci.co.uk/news/world/latin_america/rss.xml", name: "BBC Latin America" } =>
      { tier: 2, risk: "low", region: "latam" },
    { url: "https://www.theguardian.com/world/americas/rss", name: "Guardian Americas" } =>
      { tier: 2, risk: "low", region: "latam" },
    { url: "https://www.clarin.com/rss/lo-ultimo/", name: "Clarin" } =>
      { tier: 2, risk: "low", region: "latam" },
    { url: "https://feeds.folha.uol.com.br/emcimadahora/rss091.xml", name: "Folha de S.Paulo" } =>
      { tier: 2, risk: "low", region: "latam" },
    { url: "https://www.brasilparalelo.com.br/noticias/rss.xml", name: "Brasil Paralelo" } =>
      { tier: 2, risk: "low", region: "latam" },
    { url: "https://www.eltiempo.com/rss/mundo_latinoamerica.xml", name: "El Tiempo" } =>
      { tier: 2, risk: "low", region: "latam" },
    { url: "https://www.infobae.com/feeds/rss/", name: "Infobae" } =>
      { tier: 2, risk: "low", region: "latam" },
    { url: "https://www.france24.com/en/americas/rss", name: "France 24 Americas" } =>
      { tier: 2, risk: "medium", affiliation: "France", region: "latam" },
    { url: "https://www.bbc.com/mundo/index.xml", name: "BBC Mundo" } =>
      { tier: 2, risk: "low", region: "latam" },

    # US Military & OSINT (Tier 2)
    { url: "https://www.militarytimes.com/arc/outboundfeeds/rss/?outputType=xml", name: "Military Times" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://news.usni.org/feed", name: "USNI News" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://www.oryxspioenkop.com/feeds/posts/default?alt=rss", name: "Oryx OSINT" } =>
      { tier: 2, risk: "low", region: "global" },
    { url: "https://warontherocks.com/feed", name: "War on the Rocks" } =>
      { tier: 2, risk: "low", region: "global" },

    # ── TIER 3: Specialty / Think Tanks / OSINT / Defense ──────
    # Defense & Security
    { url: "https://www.bellingcat.com/feed/", name: "Bellingcat" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://www.defensenews.com/arc/outboundfeeds/rss/?outputType=xml", name: "Defense News" } =>
      { tier: 3, risk: "low", region: "us" },
    { url: "https://thewarzone.com/feed", name: "The War Zone" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://foreignpolicy.com/feed/", name: "Foreign Policy" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://www.armscontrol.org/rss.xml", name: "Arms Control Assoc." } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://www.defenseone.com/rss/all/", name: "Defense One" } =>
      { tier: 3, risk: "low", region: "us" },
    { url: "https://breakingdefense.com/feed/", name: "Breaking Defense" } =>
      { tier: 3, risk: "low", region: "us" },
    { url: "https://taskandpurpose.com/feed/", name: "Task & Purpose" } =>
      { tier: 3, risk: "low", region: "us" },
    { url: "https://gcaptain.com/feed/", name: "gCaptain" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://krebsonsecurity.com/feed/", name: "Krebs Security" } =>
      { tier: 3, risk: "low", region: "global" },

    # Think Tanks
    { url: "https://www.foreignaffairs.com/rss.xml", name: "Foreign Affairs" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://www.atlanticcouncil.org/feed/", name: "Atlantic Council" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://www.crisisgroup.org/rss", name: "Crisis Group" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://www.aei.org/feed/", name: "AEI" } =>
      { tier: 3, risk: "low", region: "us" },
    { url: "https://responsiblestatecraft.org/feed/", name: "Responsible Statecraft" } =>
      { tier: 3, risk: "low", region: "us" },
    { url: "https://www.fpri.org/feed/", name: "FPRI" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://jamestown.org/feed/", name: "Jamestown Foundation" } =>
      { tier: 3, risk: "low", region: "global" },
    { url: "https://www.fao.org/feeds/fao-newsroom-rss", name: "FAO" } =>
      { tier: 3, risk: "low", region: "global" },

    # Regional specialty
    { url: "https://www.jeuneafrique.com/feed/", name: "Jeune Afrique" } =>
      { tier: 3, risk: "low", region: "africa" },
    { url: "https://dailytrust.com/feed/", name: "Daily Trust" } =>
      { tier: 3, risk: "low", region: "africa" },
    { url: "https://thediplomat.com/feed/", name: "The Diplomat" } =>
      { tier: 3, risk: "low", region: "asia" },
    { url: "https://www.scmp.com/rss/91/feed/", name: "SCMP" } =>
      { tier: 3, risk: "low", region: "asia" },
    { url: "https://japantoday.com/feed/atom", name: "Japan Today" } =>
      { tier: 3, risk: "low", region: "asia" },
    { url: "https://islandtimes.org/feed/", name: "Island Times Palau" } =>
      { tier: 3, risk: "low", region: "oceania" },
    { url: "https://www.lasillavacia.com/rss", name: "La Silla Vacia" } =>
      { tier: 3, risk: "low", region: "latam" },
    { url: "https://insightcrime.org/feed/", name: "InSight Crime" } =>
      { tier: 3, risk: "low", region: "latam" },
    { url: "https://mexiconewsdaily.com/feed/", name: "Mexico News Daily" } =>
      { tier: 3, risk: "low", region: "latam" },
    { url: "https://www.primicias.ec/feed/", name: "Primicias Ecuador" } =>
      { tier: 3, risk: "low", region: "latam" },
    { url: "https://thehill.com/news/feed", name: "The Hill" } =>
      { tier: 3, risk: "low", region: "us" },
    { url: "https://www.in.gr/feed/", name: "in.gr" } =>
      { tier: 3, risk: "low", region: "europe" },
    { url: "https://www.iefimerida.gr/rss.xml", name: "iefimerida" } =>
      { tier: 3, risk: "low", region: "europe" },

    # State media (high propaganda risk — included for coverage, flagged)
    { url: "https://www.rt.com/rss/", name: "RT" } =>
      { tier: 3, risk: "high", affiliation: "Russia", region: "global" },
    { url: "https://feeds.bbci.co.uk/russian/rss.xml", name: "BBC Russian" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://asharq.com/snapchat/rss.xml", name: "Asharq News" } =>
      { tier: 3, risk: "medium", affiliation: "Saudi", region: "middle-east" },
    { url: "https://asharqbusiness.com/rss.xml", name: "Asharq Business" } =>
      { tier: 3, risk: "medium", affiliation: "Saudi", region: "middle-east" },
  }.freeze

  # Google News RSS proxy — for sources that block direct access or don't have RSS
  GOOGLE_NEWS_FEEDS = {
    # Global topics
    "World" => "https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en",
    "Conflict" => "https://news.google.com/rss/search?q=military+OR+war+OR+conflict+OR+attack&hl=en-US&gl=US&ceid=US:en",
    "Iran Conflict" => "https://news.google.com/rss/search?q=Iran+strike+OR+Iran+attack+OR+Iran+military+OR+IRGC+OR+Tehran+OR+Hormuz&hl=en-US&gl=US&ceid=US:en",
    "Gaza Conflict" => "https://news.google.com/rss/search?q=Gaza+OR+Hamas+OR+IDF+OR+Hezbollah+OR+West+Bank+OR+Rafah&hl=en-US&gl=US&ceid=US:en",
    "Yemen Houthis" => "https://news.google.com/rss/search?q=Houthi+OR+Yemen+strike+OR+Red+Sea+attack+OR+Bab+el-Mandeb&hl=en-US&gl=US&ceid=US:en",
    "Ukraine War" => "https://news.google.com/rss/search?q=Ukraine+war+OR+Kyiv+attack+OR+Donbas+OR+Crimea+OR+Zaporizhzhia&hl=en-US&gl=US&ceid=US:en",
    "Disaster" => "https://news.google.com/rss/search?q=earthquake+OR+tsunami+OR+hurricane+OR+wildfire+OR+flood&hl=en-US&gl=US&ceid=US:en",

    # Site-specific proxies for sources without RSS or that block cloud IPs
    "AP News" => "https://news.google.com/rss/search?q=site:apnews.com+when:1d&hl=en-US&gl=US&ceid=US:en",
    "Al Arabiya" => "https://news.google.com/rss/search?q=site:english.alarabiya.net+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Iran Intl" => "https://news.google.com/rss/search?q=site:iranintl.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Haaretz" => "https://news.google.com/rss/search?q=site:haaretz.com+when:7d&hl=en-US&gl=US&ceid=US:en",
    "Arab News" => "https://news.google.com/rss/search?q=site:arabnews.com+when:7d&hl=en-US&gl=US&ceid=US:en",
    "The National UAE" => "https://news.google.com/rss/search?q=site:thenationalnews.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Times of Israel" => "https://news.google.com/rss/search?q=site:timesofisrael.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Jerusalem Post" => "https://news.google.com/rss/search?q=site:jpost.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Rudaw" => "https://news.google.com/rss/search?q=site:rudaw.net+when:7d&hl=en-US&gl=US&ceid=US:en",
    "Amwaj Media" => "https://news.google.com/rss/search?q=site:amwaj.media+when:3d&hl=en-US&gl=US&ceid=US:en",
    "Iran Wire" => "https://news.google.com/rss/search?q=site:iranwire.com+when:3d&hl=en-US&gl=US&ceid=US:en",
    "Al-Monitor" => "https://news.google.com/rss/search?q=site:al-monitor.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "MEE" => "https://news.google.com/rss/search?q=site:middleeasteye.net+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Mada Masr" => "https://news.google.com/rss/search?q=site:madamasr.com+when:3d&hl=en-US&gl=US&ceid=US:en",
    "L'Orient Today" => "https://news.google.com/rss/search?q=site:lorientlejour.com+when:3d&hl=en-US&gl=US&ceid=US:en",
    "Kurdistan24" => "https://news.google.com/rss/search?q=site:kurdistan24.net+when:3d&hl=en-US&gl=US&ceid=US:en",
    "Ynetnews" => "https://news.google.com/rss/search?q=site:ynetnews.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Wafa" => "https://news.google.com/rss/search?q=site:english.wafa.ps+when:3d&hl=en-US&gl=US&ceid=US:en",
    "Mehr News" => "https://news.google.com/rss/search?q=site:en.mehrnews.com+when:3d&hl=en-US&gl=US&ceid=US:en",
    "Press TV" => "https://news.google.com/rss/search?q=site:presstv.ir+when:2d&hl=en-US&gl=US&ceid=US:en",
    "TRT World" => "https://news.google.com/rss/search?q=site:trtworld.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Gulf News" => "https://news.google.com/rss/search?q=site:gulfnews.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Khaleej Times" => "https://news.google.com/rss/search?q=site:khaleejtimes.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "i24NEWS" => "https://news.google.com/rss/search?q=site:i24news.tv+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Kyiv Independent" => "https://news.google.com/rss/search?q=site:kyivindependent.com+when:3d&hl=en-US&gl=US&ceid=US:en",
    "Nikkei Asia" => "https://news.google.com/rss/search?q=site:asia.nikkei.com+when:3d&hl=en-US&gl=US&ceid=US:en",
    "O Globo" => "https://news.google.com/rss/search?q=site:oglobo.globo.com+when:1d&hl=pt-BR&gl=BR&ceid=BR:pt-419",
    "Kathimerini" => "https://news.google.com/rss/search?q=site:kathimerini.gr+when:2d&hl=en-US&gl=US&ceid=US:en",
    "TASS" => "https://news.google.com/rss/search?q=site:tass.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Xinhua" => "https://news.google.com/rss/search?q=site:xinhuanet.com+when:2d&hl=en-US&gl=US&ceid=US:en",
    "Bangkok Post" => "https://news.google.com/rss/search?q=site:bangkokpost.com+when:1d&hl=en-US&gl=US&ceid=US:en",

    # US Government
    "White House" => "https://news.google.com/rss/search?q=site:whitehouse.gov+when:3d&hl=en-US&gl=US&ceid=US:en",
    "State Dept" => "https://news.google.com/rss/search?q=site:state.gov+when:3d&hl=en-US&gl=US&ceid=US:en",
    "Pentagon" => "https://news.google.com/rss/search?q=site:defense.gov+when:3d&hl=en-US&gl=US&ceid=US:en",

    # Think tanks without RSS
    "CSIS" => "https://news.google.com/rss/search?q=site:csis.org+when:7d&hl=en-US&gl=US&ceid=US:en",
    "RAND" => "https://news.google.com/rss/search?q=site:rand.org+when:7d&hl=en-US&gl=US&ceid=US:en",
    "Brookings" => "https://news.google.com/rss/search?q=site:brookings.edu+when:7d&hl=en-US&gl=US&ceid=US:en",
    "Carnegie" => "https://news.google.com/rss/search?q=site:carnegieendowment.org+when:7d&hl=en-US&gl=US&ceid=US:en",
    "RUSI" => "https://news.google.com/rss/search?q=site:rusi.org+when:3d&hl=en-US&gl=US&ceid=US:en",
  }.freeze

  GOOGLE_NEWS_META = {
    # Site proxies inherit credibility from the source
    "AP News" => { tier: 1, risk: "low", region: "global" },
    "White House" => { tier: 1, risk: "low", region: "us" },
    "State Dept" => { tier: 1, risk: "low", region: "us" },
    "Pentagon" => { tier: 1, risk: "low", region: "us" },
    "Al Arabiya" => { tier: 2, risk: "medium", affiliation: "Saudi", region: "middle-east" },
    "Times of Israel" => { tier: 2, risk: "low", region: "middle-east" },
    "Jerusalem Post" => { tier: 2, risk: "low", region: "middle-east" },
    "The National UAE" => { tier: 2, risk: "medium", affiliation: "UAE", region: "middle-east" },
    "Haaretz" => { tier: 2, risk: "low", region: "middle-east" },
    "Arab News" => { tier: 2, risk: "medium", affiliation: "Saudi", region: "middle-east" },
    "Rudaw" => { tier: 2, risk: "medium", affiliation: "Kurdistan", region: "middle-east" },
    "Amwaj Media" => { tier: 2, risk: "low", region: "middle-east" },
    "Iran Wire" => { tier: 2, risk: "medium", affiliation: "diaspora", region: "middle-east" },
    "Al-Monitor" => { tier: 2, risk: "low", region: "middle-east" },
    "MEE" => { tier: 2, risk: "medium", affiliation: "Qatar-linked", region: "middle-east" },
    "Mada Masr" => { tier: 2, risk: "low", region: "middle-east" },
    "L'Orient Today" => { tier: 2, risk: "low", region: "middle-east" },
    "Kurdistan24" => { tier: 2, risk: "medium", affiliation: "Kurdistan", region: "middle-east" },
    "Ynetnews" => { tier: 2, risk: "low", region: "middle-east" },
    "Wafa" => { tier: 3, risk: "high", affiliation: "Palestinian Authority", region: "middle-east" },
    "Mehr News" => { tier: 3, risk: "high", affiliation: "Iran", region: "middle-east" },
    "Press TV" => { tier: 3, risk: "high", affiliation: "Iran", region: "middle-east" },
    "TRT World" => { tier: 2, risk: "medium", affiliation: "Turkey", region: "middle-east" },
    "Gulf News" => { tier: 2, risk: "medium", affiliation: "UAE", region: "middle-east" },
    "Khaleej Times" => { tier: 2, risk: "medium", affiliation: "UAE", region: "middle-east" },
    "i24NEWS" => { tier: 2, risk: "medium", affiliation: "Israel", region: "middle-east" },
    "Kyiv Independent" => { tier: 2, risk: "low", region: "europe" },
    "Nikkei Asia" => { tier: 2, risk: "low", region: "asia" },
    "Bangkok Post" => { tier: 2, risk: "low", region: "asia" },
    "O Globo" => { tier: 2, risk: "low", region: "latam" },
    "Kathimerini" => { tier: 2, risk: "low", region: "europe" },
    "Iran Intl" => { tier: 3, risk: "medium", affiliation: "Saudi-backed", region: "middle-east" },
    "TASS" => { tier: 3, risk: "high", affiliation: "Russia", region: "global" },
    "Xinhua" => { tier: 3, risk: "high", affiliation: "China", region: "asia" },
  }.freeze

  THREAD_POOL_SIZE = 10

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?
      new.refresh
    end

    def stale?
      last = Rails.cache.read("rss_news_last_fetch")
      last.nil? || last < 20.minutes.ago
    end
  end

  def refresh
    all_records = []

    # Build full feed list
    all_feeds = []
    SOURCES.each { |info, meta| all_feeds << [info[:url], info[:name], meta] }
    GOOGLE_NEWS_FEEDS.each do |name, url|
      meta = GOOGLE_NEWS_META[name] || { tier: 4, risk: "low", region: "global" }
      all_feeds << [url, "GN: #{name}", meta]
    end

    # Rotate through batches — each cycle processes ~1/4 of feeds
    # so new data arrives every 5 min but each source is only hit every 20 min
    batch_idx = (Rails.cache.read("rss_batch_idx") || 0) % BATCH_COUNT
    Rails.cache.write("rss_batch_idx", batch_idx + 1)

    batch_size = (all_feeds.size.to_f / BATCH_COUNT).ceil
    batch_feeds = all_feeds.each_slice(batch_size).to_a[batch_idx] || []

    mutex = Mutex.new
    batch_feeds.each_slice(THREAD_POOL_SIZE) do |batch|
      threads = batch.map do |url, name, meta|
        Thread.new { fetch_feed(url, name, meta) }
      end
      threads.each do |t|
        records = begin; t.value; rescue => e; Rails.logger.warn("RssNewsService thread: #{e.message}"); []; end
        mutex.synchronize { all_records.concat(records) }
      end
    end

    return 0 if all_records.empty?

    existing_urls = NewsEvent.where(url: all_records.map { |r| r[:url] }).pluck(:url).to_set
    candidates = all_records.reject { |r| existing_urls.include?(r[:url]) }

    # Cross-service dedup: check titles already in DB from GDELT/MultiNews
    existing_titles = NewsEvent.where("published_at > ?", 48.hours.ago)
      .pluck(:title).compact
      .map { |t| normalize_title(t) }

    new_records = dedup_by_title(candidates, existing_titles: existing_titles)
    assign_clusters(new_records)

    if new_records.any?
      NewsEvent.upsert_all(new_records, unique_by: :url)
      record_timeline_events(
        event_type: "news", model_class: NewsEvent,
        unique_key: :url, unique_values: new_records.map { |r| r[:url] },
        time_column: :published_at
      )
      TrendingKeywordTracker.ingest(new_records) if defined?(TrendingKeywordTracker)
    end

    Rails.cache.write("rss_news_last_fetch", Time.current)
    Rails.logger.info("RssNewsService: #{new_records.size} new from batch #{batch_idx + 1}/#{BATCH_COUNT} (#{batch_feeds.size} feeds, #{all_records.size} parsed)")
    new_records.size
  rescue => e
    Rails.logger.error("RssNewsService: #{e.message}")
    0
  end

  private

  def fetch_feed(url, source_name, meta)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 8
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "GlobeTracker/1.0 (news aggregator)"
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("RssNewsService[#{source_name}]: HTTP #{response.code}")
      return []
    end

    feed = RSS::Parser.parse(response.body, false)
    return [] unless feed

    now = Time.current
    (feed.items || []).first(30).filter_map do |item|
      title = item.title&.to_s&.strip
      link = item.link.is_a?(String) ? item.link : item.link&.href
      next if title.blank? || link.blank?

      link = clean_google_url(link) if link.include?("news.google.com")

      lat, lng = geocode_title(title)
      next unless lat && lng

      threat = ThreatClassifier.classify(title)
      credibility = [("tier#{meta[:tier]}"), meta[:risk], meta[:affiliation]].compact.join("/")

      {
        url: link.truncate(2000),
        title: title.truncate(500),
        name: source_name.truncate(200),
        latitude: lat + rand(-0.1..0.1),
        longitude: lng + rand(-0.1..0.1),
        tone: threat[:tone],
        level: threat[:level],
        category: threat[:category],
        threat_level: threat[:threat],
        credibility: credibility,
        themes: threat[:keywords].first(5),
        published_at: parse_pub_date(item) || now,
        fetched_at: now,
        source: "rss",
        created_at: now,
        updated_at: now,
      }
    end
  rescue => e
    Rails.logger.warn("RssNewsService[#{source_name}]: #{e.message}")
    []
  end

  # Geocoding provided by NewsGeocodable concern

  def geocode_title(title)
    geocode_city_from_title(title) || geocode_from_title(title)
  end

  def parse_pub_date(item)
    if item.respond_to?(:pubDate) && item.pubDate
      item.pubDate.is_a?(Time) ? item.pubDate : Time.parse(item.pubDate.to_s)
    elsif item.respond_to?(:updated) && item.updated
      item.updated.is_a?(Time) ? item.updated : Time.parse(item.updated.content.to_s)
    elsif item.respond_to?(:date) && item.date
      item.date
    end
  rescue
    nil
  end

  def clean_google_url(url)
    match = url.match(/url=([^&]+)/) if url.include?("url=")
    match ? URI.decode_www_form_component(match[1]) : url
  end

  # dedup_by_title, normalize_title, jaccard provided by NewsDedupable concern
end
