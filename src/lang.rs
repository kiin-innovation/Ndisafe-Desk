use hbb_common::regex::Regex;
use std::ops::Deref;

mod ar;
mod be;
mod bg;
mod ca;
mod cn;
mod cs;
mod da;
mod de;
mod el;
mod en;
mod eo;
mod es;
mod et;
mod eu;
mod fa;
mod gu;
mod fr;
mod rw;
mod he;
mod hi;
mod hr;
mod hu;
mod id;
mod it;
mod ja;
mod ko;
mod kz;
mod lt;
mod lv;
mod nb;
mod nl;
mod pl;
mod ptbr;
mod ro;
mod ru;
mod sc;
mod sk;
mod sl;
mod sq;
mod sr;
mod sv;
mod th;
mod tr;
mod tw;
mod uk;
mod vi;
mod ta;
mod ge;
mod fi;
mod ml;

#[cfg(test)]
#[path = "lang/template.rs"]
mod template;

pub const LANGS: &[(&str, &str)] = &[
    ("en", "English"),
    ("rw", "Kinyarwanda"),
    ("fr", "Français"),
];

pub(crate) fn cjk_ui_unavailable() -> bool {
    cfg!(all(
        target_os = "linux",
        target_arch = "aarch64",
        feature = "flutter"
    ))
}

pub(crate) fn is_cjk_lang(lang_or_locale: &str) -> bool {
    let lang = lang_or_locale
        .split(|c| c == '-' || c == '_')
        .next()
        .unwrap_or_default()
        .to_lowercase();
    matches!(lang.as_str(), "zh" | "ja" | "ko")
}

fn resolve_lang(saved_lang: &str, _locale: &str, _cjk_fallback: bool) -> String {
    match saved_lang.to_lowercase().as_str() {
        "fr" => "fr",
        "rw" => "rw",
        _ => "en",
    }
    .to_owned()
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn translate(name: String) -> String {
    let locale = sys_locale::get_locale().unwrap_or_default();
    translate_locale(name, &locale)
}

pub fn translate_locale(name: String, locale: &str) -> String {
    let lang = resolve_lang(
        &hbb_common::config::LocalConfig::get_option("lang"),
        locale,
        cjk_ui_unavailable(),
    );
    let m = match lang.as_str() {
        "fr" => fr::T.deref(),
        "rw" => rw::T.deref(),
        "zh-cn" => cn::T.deref(),
        "it" => it::T.deref(),
        "zh-tw" => tw::T.deref(),
        "de" => de::T.deref(),
        "nb" => nb::T.deref(),
        "nl" => nl::T.deref(),
        "es" => es::T.deref(),
        "et" => et::T.deref(),
        "eu" => eu::T.deref(),
        "hu" => hu::T.deref(),
        "ru" => ru::T.deref(),
        "eo" => eo::T.deref(),
        "id" => id::T.deref(),
        "br" => ptbr::T.deref(),
        "pt" => ptbr::T.deref(),
        "tr" => tr::T.deref(),
        "cs" => cs::T.deref(),
        "da" => da::T.deref(),
        "sk" => sk::T.deref(),
        "vi" => vi::T.deref(),
        "pl" => pl::T.deref(),
        "ja" => ja::T.deref(),
        "ko" => ko::T.deref(),
        "kz" => kz::T.deref(),
        "uk" => uk::T.deref(),
        "fa" => fa::T.deref(),
        "fi" => fi::T.deref(),
        "ca" => ca::T.deref(),
        "el" => el::T.deref(),
        "sv" => sv::T.deref(),
        "sq" => sq::T.deref(),
        "sr" => sr::T.deref(),
        "th" => th::T.deref(),
        "sl" => sl::T.deref(),
        "ro" => ro::T.deref(),
        "lt" => lt::T.deref(),
        "lv" => lv::T.deref(),
        "ar" => ar::T.deref(),
        "bg" => bg::T.deref(),
        "be" => be::T.deref(),
        "he" => he::T.deref(),
        "hr" => hr::T.deref(),
        "sc" => sc::T.deref(),
        "ta" => ta::T.deref(),
        "ge" => ge::T.deref(),
        "ml" => ml::T.deref(),
        "hi" => hi::T.deref(),
        "gu" => gu::T.deref(),
        _ => en::T.deref(),
    };
    let (name, placeholder_value) = extract_placeholder(&name);
    let replace = |s: &&str| {
        let mut s = s.to_string();
        if let Some(value) = placeholder_value.as_ref() {
            s = s.replace("{}", &value);
        }
        if !crate::is_rustdesk() {
            if s.contains("RustDesk")
                && !name.starts_with("upgrade_rustdesk_server_pro")
                && name != "powered_by_me"
            {
                let app_name = crate::get_app_name();
                if !app_name.contains("RustDesk") {
                    s = s.replace("RustDesk", &app_name);
                } else {
                    // https://github.com/rustdesk/rustdesk-server-pro/issues/845
                    // If app_name contains "RustDesk" (e.g., "RustDesk-Admin"), we need to avoid
                    // replacing "RustDesk" within the already-substituted app_name, which would
                    // cause duplication like "RustDesk-Admin" -> "RustDesk-Admin-Admin".
                    //
                    // app_name only contains alphanumeric and hyphen.
                    const PLACEHOLDER: &str = "#A-P-P-N-A-M-E#";
                    if !s.contains(PLACEHOLDER) {
                        s = s.replace(&app_name, PLACEHOLDER);
                        s = s.replace("RustDesk", &app_name);
                        s = s.replace(PLACEHOLDER, &app_name);
                    } else {
                        // It's very unlikely to reach here.
                        // Skip replacement to avoid incorrect result.
                    }
                }
            }
        }
        s
    };
    if let Some(v) = m.get(&name as &str) {
        if !v.is_empty() {
            return replace(v);
        }
    }
    if lang != "en" {
        if let Some(v) = en::T.get(&name as &str) {
            if !v.is_empty() {
                return replace(v);
            }
        }
    }
    replace(&name.as_str())
}

// Matching pattern is {}
// Write {value} in the UI and {} in the translation file
//
// Example:
// Write in the UI: translate("There are {24} hours in a day")
// Write in the translation file: ("There are {} hours in a day", "{} hours make up a day")
fn extract_placeholder(input: &str) -> (String, Option<String>) {
    if let Ok(re) = Regex::new(r#"\{(.*?)\}"#) {
        if let Some(captures) = re.captures(input) {
            if let Some(inner_match) = captures.get(1) {
                let name = re.replace(input, "{}").to_string();
                let value = inner_match.as_str().to_string();
                return (name, Some(value));
            }
        }
    }
    (input.to_string(), None)
}

mod test {
    #[test]
    fn test_extract_placeholders() {
        use super::extract_placeholder as f;

        assert_eq!(f(""), ("".to_string(), None));
        assert_eq!(
            f("{3} sessions"),
            ("{} sessions".to_string(), Some("3".to_string()))
        );
        assert_eq!(f(" } { "), (" } { ".to_string(), None));
        // Allow empty value
        assert_eq!(
            f("{} sessions"),
            ("{} sessions".to_string(), Some("".to_string()))
        );
        // Match only the first one
        assert_eq!(
            f("{2} times {4} makes {8}"),
            ("{} times {4} makes {8}".to_string(), Some("2".to_string()))
        );
    }

    #[test]
    fn test_only_three_supported_languages() {
        assert_eq!(super::LANGS.iter().map(|x| x.0).collect::<Vec<_>>(), vec!["en", "rw", "fr"]);
    }

    #[test]
    fn test_english_is_default_regardless_of_system_locale() {
        for locale in ["en-US", "fr-FR", "rw-RW", "zh_CN", "ja-JP", "ko_KR"] {
            for cjk_fallback in [false, true] {
                assert_eq!(super::resolve_lang("", locale, cjk_fallback), "en");
                assert_eq!(super::resolve_lang("de", locale, cjk_fallback), "en");
                assert_eq!(super::resolve_lang("zh-cn", locale, cjk_fallback), "en");
            }
        }
    }

    #[test]
    fn test_explicit_supported_language_is_preserved() {
        for lang in ["en", "fr", "rw"] {
            for cjk_fallback in [false, true] {
                assert_eq!(super::resolve_lang(lang, "de-DE", cjk_fallback), lang);
                assert_eq!(super::resolve_lang(&lang.to_uppercase(), "en-US", cjk_fallback), lang);
            }
        }
    }

    #[test]
    fn test_kinyarwanda_keys_cover_template_and_preserve_placeholders() {
        assert_eq!(super::rw::T.len(), super::template::T.len());
        for key in super::template::T.keys() {
            assert!(super::rw::T.contains_key(key), "Missing Kinyarwanda key: {}", key);
        }
        for (key, value) in super::rw::T.iter().filter(|(_, value)| !value.is_empty()) {
            let source = super::en::T.get(key).filter(|v| !v.is_empty()).copied().unwrap_or(key);
            assert_eq!(source.matches("{}").count(), value.matches("{}").count(), "Placeholder mismatch: {}", key);
            for placeholder in ["%min%", "%max%"] {
                assert_eq!(source.matches(placeholder).count(), value.matches(placeholder).count(), "Placeholder mismatch: {}", key);
            }
        }
        assert_eq!(super::rw::T.get("Pause sharing"), Some(&"Hagarika gusangiza by'agateganyo"));
    }
}
