pub fn version_from_tag(tag: &str) -> Option<&str> {
    let version = tag.strip_prefix('v').unwrap_or(tag);
    parse_version(version)?;
    Some(version)
}

fn parse_version(version: &str) -> Option<[u64; 3]> {
    let mut parts = version.split('.');
    let mut numbers = [0; 3];
    for number in &mut numbers {
        let part = parts.next()?;
        if part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        *number = part.parse().ok()?;
    }
    if parts.next().is_some() {
        return None;
    }
    Some(numbers)
}

pub fn is_newer_release(tag: &str, installed: &str) -> Option<bool> {
    Some(parse_version(version_from_tag(tag)?)? > parse_version(installed)?)
}

pub fn windows_asset_name(tag: &str, arch: &str) -> String {
    let version = tag.strip_prefix('v').unwrap_or(tag);
    format!("NDISafe-Desk-{version}-windows-{arch}.exe")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sample_upgrades_are_detected() {
        for (installed, released) in [
            ("1.4.9", "1.4.10"),
            ("1.4.9", "1.5.0"),
            ("1.4.9", "v1.5.0"),
            ("1.5.0", "2.0.0"),
            ("1.9.9", "1.10.0"),
            ("1.4.99", "1.4.100"),
        ] {
            assert_eq!(is_newer_release(released, installed), Some(true));
        }
    }

    #[test]
    fn equal_and_older_releases_do_not_offer_updates() {
        for tag in ["1.4.9", "v1.4.9", "1.4.8", "1.3.99", "0.9.0"] {
            assert_eq!(is_newer_release(tag, "1.4.9"), Some(false));
        }
    }

    #[test]
    fn invalid_and_unstable_tags_are_rejected() {
        for tag in [
            "",
            "nightly",
            "1.5",
            "1.5.0.1",
            "1.5.0-beta.1",
            "1.5.0+build",
            "1.5.-1",
            "+1.5.0",
            "v",
            "v1.5.0/other",
            "1.5.0?download=1",
            "18446744073709551616.0.0",
        ] {
            assert_eq!(version_from_tag(tag), None, "{tag}");
            assert_eq!(is_newer_release(tag, "1.4.9"), None, "{tag}");
        }
        assert_eq!(is_newer_release("1.5.0", "invalid"), None);
    }

    #[test]
    fn asset_names_match_ci_even_for_prefixed_tags() {
        for tag in ["1.5.0", "v1.5.0"] {
            assert_eq!(
                windows_asset_name(tag, "x86_64"),
                "NDISafe-Desk-1.5.0-windows-x86_64.exe"
            );
            assert_eq!(
                windows_asset_name(tag, "aarch64"),
                "NDISafe-Desk-1.5.0-windows-aarch64.exe"
            );
        }
    }
}
