require "rss"
require "net/http"

class RssNewsService
  extend Refreshable
  include BatchRotation
  include TimelineRecorder
  include NewsDedupable
  include NewsGeocodable

  BATCH_COUNT = 4          # 4 batches × 5 min = each curated feed polled every 20 min
  REGISTRY_BATCH_COUNT = 12 # 12 batches × 5 min = each registry feed polled hourly
  BATCH_INTERVAL = 5       # minutes between batches

  REGISTRY_PATH = Rails.root.join("config", "news_publishers.yml")

  # Ceiling for feeds that declare no `when:Nd` window of their own.
  DEFAULT_MAX_ITEM_AGE = 7.days
  # Publishers do post slightly ahead; beyond this a date is simply wrong.
  FUTURE_PUB_DATE_SLACK = 1.day

  # NOTE: this service overrides .stale? (see below) and gates on a cache key
  # instead, so this declaration only supplies latest_fetch_at.
  refreshes model: NewsEvent, interval: BATCH_INTERVAL.minutes, scope: -> { NewsEvent.where(source: "rss") }

  # ── Source Credibility System ────────────────────────────────
  # Tier 1: Wire services, government, international organizations
  # Tier 2: Major outlets with editorial standards
  # Tier 3: Specialty, think tanks, OSINT, defense
  # Tier 4: Aggregators, blogs, search-based
  #
  # Risk: low / medium / high (propaganda risk)
  SOURCES = {
    # ── TIER 1: Wire Services & Government ─────────────────────
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

    # ── Flagship titles the sitemap probe missed ───────────────
    # These were dropped not for lacking news but because automated discovery
    # could not find them: their feeds live on separate hostnames
    # (rss.asahi.com, feeds.washingtonpost.com) at paths no guess list reaches,
    # and they no longer advertise <link rel="alternate"> on the homepage. Each
    # URL below was verified by hand -- fetched with the same honest user agent
    # the poller sends, parsed, and confirmed to carry items dated within 24h.
    #
    # Japan is the reason this matters: it had exactly one source, Sankei, the
    # most ideologically slanted of the majors. It now has five.
    { url: "https://www.cbsnews.com/latest/rss/world", name: "CBS News World" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://feeds.nbcnews.com/nbcnews/public/world", name: "NBC News World" } =>
      { tier: 2, risk: "low", region: "us" },
    { url: "https://feeds.bloomberg.com/politics/news.rss", name: "Bloomberg Politics" } =>
      { tier: 1, risk: "low", region: "us" },
    { url: "https://rss.politico.com/politics-news.xml", name: "Politico" } =>
      { tier: 2, risk: "low", affiliation: "Axel Springer", region: "us" },
    { url: "https://feeds.skynews.com/feeds/rss/world.xml", name: "Sky News World" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.lefigaro.fr/rss/figaro_actualites.xml", name: "Le Figaro" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://rss.sueddeutsche.de/rss/Topthemen", name: "Sueddeutsche Zeitung" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://rss.elconfidencial.com/mundo/", name: "El Confidencial" } =>
      { tier: 2, risk: "medium", region: "europe" },
    { url: "https://tvn24.pl/najnowsze.xml", name: "TVN24" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://www.volkskrant.nl/voorpagina/rss.xml", name: "de Volkskrant" } =>
      { tier: 2, risk: "low", region: "europe" },
    { url: "https://rss.asahi.com/rss/asahi/newsheadlines.rdf", name: "Asahi Shimbun" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://mainichi.jp/rss/etc/mainichi-flash.rss", name: "Mainichi Shimbun" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://www.nhk.or.jp/rss/news/cat0.xml", name: "NHK News" } =>
      { tier: 1, risk: "low", region: "asia" },
    { url: "https://www.japantimes.co.jp/feed/", name: "Japan Times" } =>
      { tier: 2, risk: "low", region: "asia" },
    { url: "https://timesofindia.indiatimes.com/rssfeedstopstories.cms", name: "Times of India" } =>
      { tier: 2, risk: "medium", region: "asia" },
    { url: "https://feeds.feedburner.com/ndtvnews-world-news", name: "NDTV World" } =>
      { tier: 2, risk: "medium", affiliation: "Adani", region: "asia" },
    { url: "https://www.straitstimes.com/news/world/rss.xml", name: "Straits Times" } =>
      { tier: 2, risk: "medium", affiliation: "SPH Media", region: "asia" },
    { url: "https://www.cbc.ca/webfeed/rss/rss-topstories", name: "CBC News" } =>
      { tier: 1, risk: "low", region: "us" },
    { url: "https://www.abc.net.au/news/feed/51120/rss.xml", name: "ABC Australia" } =>
      { tier: 1, risk: "low", region: "oceania" },
    { url: "https://g1.globo.com/rss/g1/mundo/", name: "G1 Mundo" } =>
      { tier: 2, risk: "low", region: "latam" },
    # Both operate under Russian state pressure -- carried for visibility into
    # domestic framing, not as independent reporting.
    { url: "https://www.kommersant.ru/RSS/news.xml", name: "Kommersant" } =>
      { tier: 2, risk: "medium", affiliation: "Russian", region: "europe" },
    { url: "https://rssexport.rbc.ru/rbcnews/news/30/full.rss", name: "RBC" } =>
      { tier: 2, risk: "medium", affiliation: "Russian", region: "europe" },
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
  MAX_REDIRECTS = 3

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?
      new.refresh
    end

    def stale?
      last = Rails.cache.read("rss_news_last_fetch")
      # Tied to BATCH_INTERVAL on purpose. The rotation cursor is clock-derived
      # with a BATCH_INTERVAL period, and BatchRotation only advances one slice
      # per poll if the poll cadence matches that period. At the old hardcoded
      # 20 minutes each poll jumped 4 slices: with BATCH_COUNT=4 that is a whole
      # lap back to the same curated batch every time, and of the 12 registry
      # slices only 3 were ever reachable. Same starvation as the cache-counter
      # cursor this rotation replaced, just arrived at from the other side.
      last.nil? || last < BATCH_INTERVAL.minutes.ago
    end

    # RSS-transport publishers from the shared registry.
    #
    # NewsSitemapService takes the sitemap-transport rows and leaves these to
    # this service -- but nothing ever read them, so 379 live-probed feeds sat
    # unused while this service polled only its hardcoded list. The registry
    # carries tier/risk/region already, which is exactly the meta shape
    # fetch_feed wants.
    def registry_feeds
      @registry_feeds ||= begin
        rows = YAML.load_file(REGISTRY_PATH)
        covered = curated_hosts

        rows.filter_map do |row|
          next unless row["transport"] == "rss"
          next if row["url"].blank?
          # Skip anything the curated list already polls, so a publisher in
          # both is fetched once and on the faster rotation.
          next if covered.any? { |h| h == row["domain"] || h.end_with?(".#{row["domain"]}") }

          [row["url"], row["domain"], { tier: row["tier"], risk: row["risk"], region: row["region"] }.compact]
        end
      rescue Errno::ENOENT
        Rails.logger.warn("RssNewsService: #{REGISTRY_PATH} missing")
        []
      end
    end

    def reload_registry_feeds!
      @registry_feeds = nil
      registry_feeds
    end

    private

    def curated_hosts
      SOURCES.keys.filter_map do |info|
        URI.parse(info[:url]).host&.downcase&.delete_prefix("www.")
      rescue URI::InvalidURIError
        nil
      end
    end
  end

  def refresh
    all_records = []
    ingest_items = []

    # The curated feeds stay on their own fast rotation: they are the tier-1
    # wires, and their RSS windows are shallow enough that folding them into a
    # list four times longer would start losing items between polls.
    curated = []
    SOURCES.each { |info, meta| curated << [info[:url], info[:name], meta] }
    GOOGLE_NEWS_FEEDS.each do |name, url|
      meta = GOOGLE_NEWS_META[name] || { tier: 4, risk: "low", region: "global" }
      curated << [url, "GN: #{name}", meta]
    end

    # Rotate through batches — each cycle processes ~1/4 of feeds
    # so new data arrives every 5 min but each source is only hit every 20 min
    batch_idx = rotation_index(BATCH_COUNT, period: BATCH_INTERVAL.minutes)
    batch_feeds = rotation_slice(curated, BATCH_COUNT, period: BATCH_INTERVAL.minutes)

    # The registry is much longer and mostly lower-volume, so it rides a slower
    # cursor: a comparable number of feeds per cycle, an hour to come round.
    batch_feeds += rotation_slice(
      self.class.registry_feeds, REGISTRY_BATCH_COUNT, period: BATCH_INTERVAL.minutes
    )

    mutex = Mutex.new
    batch_feeds.shuffle.each_slice(THREAD_POOL_SIZE) do |batch|
      threads = batch.map do |url, name, meta|
        Thread.new do
          sleep(rand * 3) # 0-3s jitter per feed within each thread group
          begin
            fetch_feed(url, name, meta)
          ensure
            # fetch_feed writes a SourceFeedStatus row, so every one of these
            # threads checks out a pooled connection and holds it until the
            # thread dies. Ten fan-out threads against a pool of 5 starved the
            # main thread, which then failed its own checkout and discarded the
            # entire parsed batch. Hand the connection back immediately.
            ActiveRecord::Base.connection_pool.release_connection
          end
        end
      end
      threads.each do |t|
        result = begin
          t.value
        rescue => e
          Rails.logger.warn("RssNewsService thread: #{e.message}")
          { records: [], ingest_items: [] }
        end
        mutex.synchronize do
          all_records.concat(result[:records])
          ingest_items.concat(result[:ingest_items])
        end
      end
    end

    return 0 if all_records.empty?

    existing_urls = NewsEvent.where(url: all_records.map { |r| r[:url] }).pluck(:url).to_set
    candidates = dedup_by_url(all_records.reject { |r| existing_urls.include?(r[:url]) })

    # Suppress a publisher re-running its own headline. Matching headlines from
    # *other* publishers are kept on purpose -- see NewsDedupable#dedup_by_title.
    existing = NewsEvent.where("published_at > ?", 48.hours.ago).pluck(:url, :title)

    new_records = dedup_by_title(candidates, existing: existing)
    ingest_ids = NewsIngestRecorder.record_all(ingest_items)
    new_records.each { |record| record[:news_ingest_id] = ingest_ids[record[:url]] }
    normalized_ids = NewsNormalizationRecorder.record_all(new_records)
    NewsNormalizationRecorder.apply_ids!(new_records, normalized_ids)
    NewsClaimRecorder.record_all(new_records)
    RssArticleHydrationService.enqueue_candidates(new_records)

    if new_records.any?
      # Events before clustering -- see the note in NewsSitemapService: the
      # cluster rebuild reads each member's location off its news_events, so a
      # cluster built before the event exists is stranded at article_count: 0.
      NewsEvent.upsert_all(new_records, unique_by: :url)
      assign_clusters(new_records)
      NewsOntologySyncService.enqueue_for_records(new_records)

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
    # Loud on purpose: this rescue quietly returned 0 for three months while
    # upsert_all rejected every batch, and the poller kept reporting a clean
    # cycle. Say how much was thrown away.
    Rails.logger.error(
      "RssNewsService: #{e.class}: #{e.message} -- discarded #{new_records&.size || all_records.size} records"
    )
    Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
    0
  end

  private

  # Feeds move, and Net::HTTP does not follow the hop on its own. 36 of the 356
  # publishers answered with a 3xx inside a single hour and every one was
  # recorded as an error and dropped, so those publishers contributed nothing at
  # all. Follow the redirect instead, with a hop cap and a loop guard.
  def http_get_following_redirects(url, limit: MAX_REDIRECTS)
    current = url
    seen = Set.new
    response = nil

    (limit + 1).times do
      uri = URI(current)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 8
      http.read_timeout = 15

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "GlobeTracker/1.0 (news aggregator)"
      response = http.request(request)

      return response unless response.is_a?(Net::HTTPRedirection)

      location = response["location"].to_s
      return response if location.blank?

      seen << current
      # Location is allowed to be relative; URI.join resolves it against the
      # URL we actually requested.
      nxt = begin
        URI.join(current, location).to_s
      rescue URI::Error
        return response
      end
      return response if seen.include?(nxt)

      current = nxt
    end

    response
  end

  def fetch_feed(url, source_name, meta)
    now = Time.current
    response = http_get_following_redirects(url)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("RssNewsService[#{source_name}]: HTTP #{response.code}")
      SourceFeedStatusRecorder.record(
        provider: "rss",
        display_name: source_name,
        feed_kind: "rss",
        endpoint_url: url,
        status: "error",
        http_status: response.code.to_i,
        error_message: "HTTP #{response.code}",
        metadata: { tier: meta[:tier], region: meta[:region], risk: meta[:risk] }.compact,
        occurred_at: now
      )
      return { records: [], ingest_items: [] }
    end

    feed = RSS::Parser.parse(response.body, false)
    unless feed
      SourceFeedStatusRecorder.record(
        provider: "rss",
        display_name: source_name,
        feed_kind: "rss",
        endpoint_url: url,
        status: "error",
        http_status: response.code.to_i,
        error_message: "RSS parse returned nil",
        metadata: { tier: meta[:tier], region: meta[:region], risk: meta[:risk] }.compact,
        occurred_at: now
      )
      return { records: [], ingest_items: [] }
    end

    records = []
    ingest_items = []

    (feed.items || []).first(30).each_with_index do |item, idx|
      title = item.title&.to_s&.strip
      raw_link = item.link.is_a?(String) ? item.link : item.link&.href
      next if title.blank? || raw_link.blank?

      published_at = parse_pub_date(item)
      next if item_outside_feed_window?(published_at, url, now: now)

      link = raw_link.include?("news.google.com") ? clean_google_url(raw_link) : raw_link
      summary = rss_item_summary(item)
      adapted = NewsSourceAdapter.normalize!(
        source_adapter: "rss:#{source_name.parameterize}",
        attrs: {
          url: link,
          title: title,
          summary: summary,
          name: source_name,
          published_at: published_at,
          source: "rss",
        }
      )
      ingest_items << {
        item_key: adapted[:url].presence || "#{source_name}-#{idx}",
        source_feed: source_name,
        source_endpoint_url: url,
        external_id: rss_item_guid(item),
        raw_url: raw_link,
        raw_title: adapted[:title],
        raw_summary: adapted[:summary],
        raw_published_at: published_at,
        fetched_at: now,
        payload_format: "rss",
        raw_payload: rss_item_payload(item, raw_link),
        http_status: response.code.to_i,
      }

      location = LocationResolver.resolve_event(
        title: adapted[:title],
        summary: adapted[:summary],
        url: adapted[:url],
        publisher: item_publisher(item, source_name)
      )
      next unless location&.coordinates

      threat = ThreatClassifier.classify([ adapted[:title], adapted[:summary] ].compact.join(" "))
      credibility = [("tier#{meta[:tier]}"), meta[:risk], meta[:affiliation]].compact.join("/")

      records << LocationResolver.news_event_attributes(location).merge(
        url: adapted[:url],
        title: adapted[:title],
        name: adapted[:name],
        tone: threat[:tone],
        level: threat[:level],
        category: threat[:category],
        threat_level: threat[:threat],
        credibility: credibility,
        themes: threat[:keywords].first(5),
        published_at: adapted[:published_at] || now,
        fetched_at: now,
        source: "rss",
        created_at: now,
        updated_at: now,
      )
    end
    SourceFeedStatusRecorder.record(
      provider: "rss",
      display_name: source_name,
      feed_kind: "rss",
      endpoint_url: url,
      status: "success",
      records_fetched: Array(feed.items).size,
      records_stored: records.size,
      http_status: response.code.to_i,
      metadata: { tier: meta[:tier], region: meta[:region], risk: meta[:risk] }.compact,
      occurred_at: now
    )

    { records: records, ingest_items: ingest_items }
  rescue => e
    Rails.logger.warn("RssNewsService[#{source_name}]: #{e.message}")
    SourceFeedStatusRecorder.record(
      provider: "rss",
      display_name: source_name,
      feed_kind: "rss",
      endpoint_url: url,
      status: "error",
      error_message: e.message,
      metadata: { tier: meta[:tier], region: meta[:region], risk: meta[:risk] }.compact,
      occurred_at: now || Time.current
    )
    { records: [], ingest_items: [] }
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

  # Google News `when:Nd` bounds when Google last *indexed* a page, not the
  # pubDate it reports back. So a `site:` search happily returns homepages,
  # section landing pages, paginated indexes and author profiles -- static pages
  # it re-crawled recently -- each carrying its original publication date.
  # Production ingested a Brookings landing page dated 2006 and a White House
  # index page dated 2017 this way, and nothing downstream rejected them, so
  # they reached the timeline as real events. Hold every item to its own feed's
  # declared window.
  def item_outside_feed_window?(published_at, feed_url, now:)
    # A feed that omits a date is not evidence of staleness; other filters catch those.
    return false if published_at.blank?
    return true if published_at > now + FUTURE_PUB_DATE_SLACK

    published_at < now - max_item_age_for(feed_url)
  end

  def max_item_age_for(feed_url)
    match = feed_url.to_s.match(/when:(\d+)([dh])/i)
    return DEFAULT_MAX_ITEM_AGE unless match

    unit = match[2].casecmp?("h") ? 1.hour : 1.day
    # Google's window is inclusive and pubDates drift across timezones, so leave
    # a day of slack rather than trimming genuine articles at the boundary.
    (match[1].to_i * unit) + 1.day
  end

  def clean_google_url(url)
    match = url.match(/url=([^&]+)/) if url.include?("url=")
    match ? URI.decode_www_form_component(match[1]) : url
  end

  def rss_item_guid(item)
    return nil unless item.respond_to?(:guid) && item.guid.present?

    item.guid.respond_to?(:content) ? item.guid.content : item.guid.to_s
  end

  def rss_item_summary(item)
    if item.respond_to?(:description) && item.description.present?
      item.description.to_s
    elsif item.respond_to?(:summary) && item.summary.present?
      item.summary.to_s
    elsif item.respond_to?(:content_encoded) && item.content_encoded.present?
      item.content_encoded.to_s
    end
  end

  # Who filed the story, for the sole purpose of keeping their masthead out of
  # the geocoder. Google News appends the publisher to every headline and names
  # it in <source>, which is the accurate answer on the mixed topic feeds where
  # the feed name is "World". A single-site feed has no <source>, and there the
  # feed name is the publisher.
  def item_publisher(item, source_name)
    google = item.source&.content&.to_s&.squish if item.respond_to?(:source)
    google.presence || source_name
  rescue StandardError
    source_name
  end

  def rss_item_payload(item, raw_link)
    {
      "title" => item.title&.to_s,
      "link" => raw_link,
      "description" => rss_item_summary(item),
      "guid" => rss_item_guid(item),
      "pub_date" => parse_pub_date(item)&.iso8601,
      "categories" => (item.respond_to?(:categories) ? Array(item.categories).map(&:to_s) : []),
      "author" => (item.respond_to?(:author) ? item.author&.to_s : nil),
    }.compact
  end

  # dedup_by_title, normalize_title, jaccard provided by NewsDedupable concern
end
