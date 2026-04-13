import Foundation

// MARK: - Supported Languages

enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case german = "de"
    case dutch = "nl"
    case serbian = "sr"
    case austrian = "at"
    case newZealand = "nz"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .dutch: return "Nederlands"
        case .serbian: return "Српски"
        case .austrian: return "Österreichisch"
        case .newZealand: return "New Zealandian"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .german: return "🇩🇪"
        case .dutch: return "🇳🇱"
        case .serbian: return "🇷🇸"
        case .austrian: return "🇦🇹"
        case .newZealand: return "🇳🇿"
        }
    }

    /// The language whose translations this variant uses.
    var translationSource: AppLanguage {
        switch self {
        case .austrian: return .german
        case .newZealand: return .english
        default: return self
        }
    }
}

// MARK: - Localization Keys

enum L {
    // Usage section
    static var sessionTitle: String { loc("Session (5h)") }
    static var weeklyTitle: String { loc("Weekly (7d)") }
    static var sonnetTitle: String { loc("Sonnet") }
    static var resetIn: String { loc("reset in") }
    static var updated: String { loc("Updated") }

    // Menu items
    static var settings: String { loc("Settings") }
    static var usageOnClaude: String { loc("Usage on claude.ai") }
    static var refreshNow: String { loc("Refresh Now") }
    static var quit: String { loc("Quit") }
    static var launchAtLogin: String { loc("Launch at Login") }
    static var logIn: String { loc("Log In") }
    static var logout: String { loc("Logout") }

    // Not logged in
    static var notLoggedIn: String { loc("Not logged in") }
    static var openAppToLogIn: String { loc("Open the app to log in") }

    // Section headers
    static var usageChart: String { loc("USAGE CHART") }
    static var menuBarDisplay: String { loc("MENU BAR DISPLAY") }
    static var refreshInterval: String { loc("REFRESH INTERVAL") }
    static var language: String { loc("LANGUAGE") }

    // Display toggles
    static var sessionPercent: String { loc("Session %") }
    static var sessionResetTime: String { loc("Session reset time") }
    static var weeklyPercent: String { loc("Weekly %") }
    static var weeklyResetTime: String { loc("Weekly reset time") }
    static var sonnetPercent: String { loc("Sonnet %") }
    static var sonnetResetTime: String { loc("Sonnet reset time") }

    // Chart
    static var off: String { loc("Off") }
    static var usageOverTime: String { loc("Usage Over Time") }
    static var noUsageDataYet: String { loc("No usage data yet") }
    static var dataWillAppear: String { loc("Data will appear here as usage is tracked over time.") }
    static var noDataForPeriod: String { loc("No data for this period") }

    // Login
    static var logInToClaude: String { loc("Log in to Claude") }
    static var chooseLoginMethod: String { loc("Choose a login method") }
    static var signInHere: String { loc("Sign in here") }
    static var signInHereDesc: String { loc("Log in directly in this window. Works for email/password and Google accounts.") }
    static var importFromBrowser: String { loc("Import from browser") }
    static var importFromBrowserDesc: String { loc("Already logged in via your browser (e.g. with SSO)? Import your session cookies.") }
    static var connected: String { loc("Connected") }
    static var connect: String { loc("Connect") }
    static var back: String { loc("Back") }
    static var cancel: String { loc("Cancel") }
    static var loginSuccessful: String { loc("Login successful! Fetching data...") }
    static var pleaseLogIn: String { loc("Please log in to your Claude account") }
    static var capturingSession: String { loc("Capturing session...") }
    static var couldNotCapture: String { loc("Could not capture session. Please try again.") }
    static var validatingSession: String { loc("Validating session...") }

    // Browser cookie import
    static var openClaudeInBrowser: String { loc("Open claude.ai in your browser") }
    static var logInWithSSO: String { loc("Log in with SSO or any method your browser supports.") }
    static var openInBrowser: String { loc("Open claude.ai in browser") }
    static var copyCookies: String { loc("Copy cookies from your browser") }
    static var copyInstructions: String { loc("Once logged in, open Developer Tools and copy your cookies:") }
    static var pasteCookiesBelow: String { loc("Paste cookies below") }
    static var pasteCookiePrompt: String { loc("Paste the cookie header or JSON:") }
    static var cookieTip: String { loc("Tip: You can also paste the JSON from the Cookies tab in dev tools — both formats work.") }
    static var pasteCookieError: String { loc("Please paste your cookie string or JSON.") }
    static var parseCookieError: String { loc("Could not parse cookies. Paste either the Cookie header value (key=value; ...) or the JSON from your browser's dev tools.") }
    static var couldNotAuth: String { loc("Could not authenticate with these cookies. Make sure you copied the full Cookie header value.") }

    // Error messages
    static var errorNotLoggedIn: String { loc("Not logged in") }
    static var errorOrgFailed: String { loc("Could not determine organization — session may have expired") }
    static var errorSessionExpired: String { loc("Session expired – please log in again") }
    static var errorUnexpectedFormat: String { loc("Unexpected response format") }

    // Content view
    static var claudeUsage: String { loc("Claude Usage") }
    static var logInToSeeUsage: String { loc("Log in to Claude to see your usage") }
    static var settingsTitle: String { loc("Settings") }
    static var refreshEvery: String { loc("Refresh every") }
    static var restartToApply: String { loc("Restart to apply language change") }
    static var restartNow: String { loc("Restart Now") }
    static var org: String { loc("Org:") }

    // Reset time (parameterized)
    static func resetsInDays(_ n: Int) -> String { loc("Resets in %d").replacingOccurrences(of: "%d", with: "\(n)") + loc("d_suffix") }
    static func resetsInHours(_ n: Int) -> String { loc("Resets in %d").replacingOccurrences(of: "%d", with: "\(n)") + loc("h_suffix") }
    static func resetsInMinutes(_ n: Int) -> String { loc("Resets in %d").replacingOccurrences(of: "%d", with: "\(n)") + loc("m_suffix") }
    static var resetsSoon: String { loc("Resets soon") }
    static var resetsNow: String { loc("now") }
    static var resetsUnknown: String { loc("unknown") }

    // Compact reset (just the duration part)
    static func compactDays(_ n: Int) -> String { "\(n)" + loc("d_suffix") }
    static func compactHours(_ n: Int) -> String { "\(n)" + loc("h_suffix") }
    static func compactMinutes(_ n: Int) -> String { "\(n)" + loc("m_suffix") }
    static var compactSoon: String { loc("soon") }
    static var compactNow: String { loc("now") }

    // MARK: - Lookup

    private static func loc(_ key: String) -> String {
        let lang = currentLanguage.translationSource
        if let table = translations[lang], let value = table[key] {
            return value
        }
        return key // Fallback to English (the key itself)
    }

    static var currentLanguage: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: SharedDefaults.languageKey),
              let lang = AppLanguage(rawValue: raw) else {
            return .english
        }
        return lang
    }
}

// MARK: - Translation Tables

extension L {
    private static let translations: [AppLanguage: [String: String]] = [
        .english: [
            // Suffixes for reset durations
            "d_suffix": "d",
            "h_suffix": "h",
            "m_suffix": "m",
            "Resets in %d": "Resets in %d",
            "soon": "soon",
        ],

        .german: [
            "Session (5h)": "Sitzung (5h)",
            "Weekly (7d)": "Wöchentlich (7d)",
            "Sonnet": "Sonnet",
            "reset in": "Reset in",
            "Updated": "Aktualisiert",
            "Settings": "Einstellungen",
            "Usage on claude.ai": "Nutzung auf claude.ai",
            "Refresh Now": "Jetzt aktualisieren",
            "Quit": "Beenden",
            "Launch at Login": "Bei Anmeldung starten",
            "Log In": "Anmelden",
            "Logout": "Abmelden",
            "Not logged in": "Nicht angemeldet",
            "Open the app to log in": "App öffnen zum Anmelden",
            "USAGE CHART": "NUTZUNGSDIAGRAMM",
            "MENU BAR DISPLAY": "MENÜLEISTE",
            "REFRESH INTERVAL": "AKTUALISIERUNG",
            "LANGUAGE": "SPRACHE",
            "Session %": "Sitzung %",
            "Session reset time": "Sitzung Reset-Zeit",
            "Weekly %": "Wöchentlich %",
            "Weekly reset time": "Wöchentlich Reset-Zeit",
            "Sonnet %": "Sonnet %",
            "Sonnet reset time": "Sonnet Reset-Zeit",
            "Off": "Aus",
            "Usage Over Time": "Nutzung im Zeitverlauf",
            "No usage data yet": "Noch keine Nutzungsdaten",
            "Data will appear here as usage is tracked over time.": "Daten erscheinen hier, sobald die Nutzung erfasst wird.",
            "No data for this period": "Keine Daten für diesen Zeitraum",
            "Log in to Claude": "Bei Claude anmelden",
            "Choose a login method": "Anmeldemethode wählen",
            "Sign in here": "Hier anmelden",
            "Log in directly in this window. Works for email/password and Google accounts.": "Direkt in diesem Fenster anmelden. Funktioniert mit E-Mail/Passwort und Google-Konten.",
            "Import from browser": "Aus Browser importieren",
            "Already logged in via your browser (e.g. with SSO)? Import your session cookies.": "Bereits über den Browser angemeldet (z.B. mit SSO)? Session-Cookies importieren.",
            "Connected": "Verbunden",
            "Connect": "Verbinden",
            "Back": "Zurück",
            "Cancel": "Abbrechen",
            "Login successful! Fetching data...": "Anmeldung erfolgreich! Daten werden geladen...",
            "Please log in to your Claude account": "Bitte melden Sie sich bei Claude an",
            "Capturing session...": "Sitzung wird erfasst...",
            "Could not capture session. Please try again.": "Sitzung konnte nicht erfasst werden. Bitte erneut versuchen.",
            "Validating session...": "Sitzung wird überprüft...",
            "Open claude.ai in your browser": "claude.ai im Browser öffnen",
            "Log in with SSO or any method your browser supports.": "Mit SSO oder einer anderen Methode anmelden.",
            "Open claude.ai in browser": "claude.ai im Browser öffnen",
            "Copy cookies from your browser": "Cookies aus dem Browser kopieren",
            "Once logged in, open Developer Tools and copy your cookies:": "Nach der Anmeldung die Entwicklertools öffnen und Cookies kopieren:",
            "Paste cookies below": "Cookies unten einfügen",
            "Paste the cookie header or JSON:": "Cookie-Header oder JSON einfügen:",
            "Tip: You can also paste the JSON from the Cookies tab in dev tools — both formats work.": "Tipp: Sie können auch das JSON aus dem Cookies-Tab der Entwicklertools einfügen — beide Formate funktionieren.",
            "Please paste your cookie string or JSON.": "Bitte Cookie-String oder JSON einfügen.",
            "Could not parse cookies. Paste either the Cookie header value (key=value; ...) or the JSON from your browser's dev tools.": "Cookies konnten nicht gelesen werden. Fügen Sie den Cookie-Header (key=value; ...) oder das JSON aus den Entwicklertools ein.",
            "Could not authenticate with these cookies. Make sure you copied the full Cookie header value.": "Authentifizierung fehlgeschlagen. Stellen Sie sicher, dass der vollständige Cookie-Header kopiert wurde.",
            "Could not determine organization — session may have expired": "Organisation konnte nicht ermittelt werden — Sitzung möglicherweise abgelaufen",
            "Session expired – please log in again": "Sitzung abgelaufen – bitte erneut anmelden",
            "Unexpected response format": "Unerwartetes Antwortformat",
            "Claude Usage": "Claude Nutzung",
            "Log in to Claude to see your usage": "Bei Claude anmelden, um die Nutzung zu sehen",

            "Refresh every": "Aktualisierung alle",
            "Restart to apply language change": "Neustart für Sprachwechsel erforderlich",
            "Restart Now": "Jetzt neu starten",
            "Org:": "Org:",
            // Reset time
            "d_suffix": "T",
            "h_suffix": "h",
            "m_suffix": "m",
            "Resets in %d": "Reset in %d",
            "Resets soon": "Reset bald",
            "now": "jetzt",
            "unknown": "unbekannt",
            "soon": "bald",
        ],

        .dutch: [
            "Session (5h)": "Sessie (5u)",
            "Weekly (7d)": "Wekelijks (7d)",
            "Sonnet": "Sonnet",
            "reset in": "reset in",
            "Updated": "Bijgewerkt",
            "Settings": "Instellingen",
            "Usage on claude.ai": "Gebruik op claude.ai",
            "Refresh Now": "Nu vernieuwen",
            "Quit": "Stop",
            "Launch at Login": "Open bij inloggen",
            "Log In": "Inloggen",
            "Logout": "Uitloggen",
            "Not logged in": "Niet ingelogd",
            "Open the app to log in": "Open de app om in te loggen",
            "USAGE CHART": "GEBRUIKSGRAFIEK",
            "MENU BAR DISPLAY": "MENUBALK WEERGAVE",
            "REFRESH INTERVAL": "VERNIEUWINGSINTERVAL",
            "LANGUAGE": "TAAL",
            "Session %": "Sessie %",
            "Session reset time": "Sessie resettijd",
            "Weekly %": "Wekelijks %",
            "Weekly reset time": "Wekelijks resettijd",
            "Sonnet %": "Sonnet %",
            "Sonnet reset time": "Sonnet resettijd",
            "Off": "Uit",
            "Usage Over Time": "Gebruik in de tijd",
            "No usage data yet": "Nog geen gebruiksgegevens",
            "Data will appear here as usage is tracked over time.": "Gegevens verschijnen hier naarmate het gebruik wordt bijgehouden.",
            "No data for this period": "Geen gegevens voor deze periode",
            "Log in to Claude": "Inloggen bij Claude",
            "Choose a login method": "Kies een inlogmethode",
            "Sign in here": "Hier inloggen",
            "Log in directly in this window. Works for email/password and Google accounts.": "Log direct in via dit venster. Werkt met e-mail/wachtwoord en Google-accounts.",
            "Import from browser": "Importeren uit browser",
            "Already logged in via your browser (e.g. with SSO)? Import your session cookies.": "Al ingelogd via je browser (bijv. met SSO)? Importeer je sessiecookies.",
            "Connected": "Verbonden",
            "Connect": "Verbinden",
            "Back": "Terug",
            "Cancel": "Annuleren",
            "Login successful! Fetching data...": "Inloggen gelukt! Gegevens worden opgehaald...",
            "Please log in to your Claude account": "Log in op je Claude-account",
            "Capturing session...": "Sessie vastleggen...",
            "Could not capture session. Please try again.": "Sessie kon niet worden vastgelegd. Probeer het opnieuw.",
            "Validating session...": "Sessie valideren...",
            "Open claude.ai in your browser": "Open claude.ai in je browser",
            "Log in with SSO or any method your browser supports.": "Log in met SSO of een andere methode die je browser ondersteunt.",
            "Open claude.ai in browser": "Open claude.ai in browser",
            "Copy cookies from your browser": "Kopieer cookies uit je browser",
            "Once logged in, open Developer Tools and copy your cookies:": "Eenmaal ingelogd, open de ontwikkeltools en kopieer je cookies:",
            "Paste cookies below": "Plak cookies hieronder",
            "Paste the cookie header or JSON:": "Plak de cookie-header of JSON:",
            "Tip: You can also paste the JSON from the Cookies tab in dev tools — both formats work.": "Tip: Je kunt ook de JSON uit het Cookies-tabblad van de ontwikkeltools plakken — beide formaten werken.",
            "Please paste your cookie string or JSON.": "Plak je cookie-string of JSON.",
            "Could not parse cookies. Paste either the Cookie header value (key=value; ...) or the JSON from your browser's dev tools.": "Cookies konden niet worden gelezen. Plak de Cookie-header (key=value; ...) of de JSON uit de ontwikkeltools.",
            "Could not authenticate with these cookies. Make sure you copied the full Cookie header value.": "Kon niet authenticeren met deze cookies. Zorg ervoor dat de volledige Cookie-header is gekopieerd.",
            "Could not determine organization — session may have expired": "Organisatie kon niet worden bepaald — sessie mogelijk verlopen",
            "Session expired – please log in again": "Sessie verlopen – log opnieuw in",
            "Unexpected response format": "Onverwacht antwoordformaat",
            "Claude Usage": "Claude Gebruik",
            "Log in to Claude to see your usage": "Log in bij Claude om je gebruik te bekijken",
            "Refresh every": "Vernieuw elke",
            "Restart to apply language change": "Herstart om taalwijziging toe te passen",
            "Restart Now": "Nu herstarten",
            "Org:": "Org:",
            // Reset time
            "d_suffix": "d",
            "h_suffix": "u",
            "m_suffix": "m",
            "Resets in %d": "Reset in %d",
            "Resets soon": "Reset binnenkort",
            "now": "nu",
            "unknown": "onbekend",
            "soon": "binnenkort",
        ],

        .serbian: [
            "Session (5h)": "Сесија (5h)",
            "Weekly (7d)": "Недељно (7d)",
            "Sonnet": "Sonnet",
            "reset in": "ресет за",
            "Updated": "Ажурирано",
            "Settings": "Подешавања",
            "Usage on claude.ai": "Коришћење на claude.ai",
            "Refresh Now": "Освежи сада",
            "Quit": "Затвори",
            "Launch at Login": "Покрени при пријави",
            "Log In": "Пријави се",
            "Logout": "Одјави се",
            "Not logged in": "Нисте пријављени",
            "Open the app to log in": "Отворите апликацију за пријаву",
            "USAGE CHART": "ГРАФИКОН КОРИШЋЕЊА",
            "MENU BAR DISPLAY": "ПРИКАЗ У МЕНИЈУ",
            "REFRESH INTERVAL": "ИНТЕРВАЛ ОСВЕЖАВАЊА",
            "LANGUAGE": "ЈЕЗИК",
            "Session %": "Сесија %",
            "Session reset time": "Сесија време ресета",
            "Weekly %": "Недељно %",
            "Weekly reset time": "Недељно време ресета",
            "Sonnet %": "Sonnet %",
            "Sonnet reset time": "Sonnet време ресета",
            "Off": "Искључено",
            "Usage Over Time": "Коришћење током времена",
            "No usage data yet": "Још нема података",
            "Data will appear here as usage is tracked over time.": "Подаци ће се појавити овде како се коришћење прати.",
            "No data for this period": "Нема података за овај период",
            "Log in to Claude": "Пријавите се на Claude",
            "Choose a login method": "Изаберите метод пријаве",
            "Sign in here": "Пријавите се овде",
            "Log in directly in this window. Works for email/password and Google accounts.": "Пријавите се директно у овом прозору. Ради са е-поштом/лозинком и Google налозима.",
            "Import from browser": "Увези из прегледача",
            "Already logged in via your browser (e.g. with SSO)? Import your session cookies.": "Већ сте пријављени преко прегледача (нпр. са SSO)? Увезите колачиће сесије.",
            "Connected": "Повезано",
            "Connect": "Повежи",
            "Back": "Назад",
            "Cancel": "Откажи",
            "Login successful! Fetching data...": "Пријава успешна! Преузимање података...",
            "Please log in to your Claude account": "Пријавите се на ваш Claude налог",
            "Capturing session...": "Преузимање сесије...",
            "Could not capture session. Please try again.": "Сесија није преузета. Покушајте поново.",
            "Validating session...": "Провера сесије...",
            "Open claude.ai in your browser": "Отворите claude.ai у прегледачу",
            "Log in with SSO or any method your browser supports.": "Пријавите се са SSO или другим методом.",
            "Open claude.ai in browser": "Отвори claude.ai у прегледачу",
            "Copy cookies from your browser": "Копирајте колачиће из прегледача",
            "Once logged in, open Developer Tools and copy your cookies:": "Након пријаве, отворите Developer Tools и копирајте колачиће:",
            "Paste cookies below": "Налепите колачиће испод",
            "Paste the cookie header or JSON:": "Налепите Cookie header или JSON:",
            "Tip: You can also paste the JSON from the Cookies tab in dev tools — both formats work.": "Савет: Можете налепити и JSON из Cookies картице — оба формата раде.",
            "Please paste your cookie string or JSON.": "Налепите cookie string или JSON.",
            "Could not parse cookies. Paste either the Cookie header value (key=value; ...) or the JSON from your browser's dev tools.": "Колачићи нису препознати. Налепите Cookie header (key=value; ...) или JSON из Developer Tools.",
            "Could not authenticate with these cookies. Make sure you copied the full Cookie header value.": "Аутентификација неуспешна. Проверите да сте копирали цео Cookie header.",
            "Could not determine organization — session may have expired": "Организација није пронађена — сесија је можда истекла",
            "Session expired – please log in again": "Сесија је истекла – пријавите се поново",
            "Unexpected response format": "Неочекиван формат одговора",
            "Claude Usage": "Claude Коришћење",
            "Log in to Claude to see your usage": "Пријавите се на Claude да видите коришћење",
            "Refresh every": "Освежи сваких",
            "Restart to apply language change": "Поново покрените за промену језика",
            "Restart Now": "Поново покрени",
            "Org:": "Орг:",
            // Reset time
            "d_suffix": "д",
            "h_suffix": "ч",
            "m_suffix": "м",
            "Resets in %d": "Ресет за %d",
            "Resets soon": "Ресет ускоро",
            "now": "сада",
            "unknown": "непознато",
            "soon": "ускоро",
        ],
    ]
}
