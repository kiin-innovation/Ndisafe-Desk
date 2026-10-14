pub fn install_name(display_name: &str) -> &str {
    match display_name {
        "NDISafe Desk" => "Ndisafe-desk",
        other => other,
    }
}

pub fn privilege_template(source: &str, display_name: &str, bundle_id: &str) -> String {
    let name = install_name(display_name);
    source
        .replace("com.carriez.rustdesk", bundle_id)
        .replace(
            "/Applications/RustDesk.app/Contents/MacOS/RustDesk",
            &format!("/Applications/{name}.app/Contents/MacOS/{name}"),
        )
        .replace(
            "/Applications/RustDesk.app",
            &format!("/Applications/{name}.app"),
        )
        .replace(
            "com.carriez.RustDesk_service",
            &format!("com.carriez.{name}_service"),
        )
        .replace(
            "com.carriez.RustDesk_server",
            &format!("com.carriez.{name}_server"),
        )
        .replace("pgrep -x 'RustDesk'", &format!("pgrep -x '{name}'"))
        .replace("rustdesk", &name.to_lowercase())
        .replace("RustDesk", display_name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn install_paths_match_the_xcode_product() {
        let settings = include_str!("../../flutter/macos/Runner/Configs/AppInfo.xcconfig");
        assert!(settings
            .lines()
            .any(|line| line == format!("PRODUCT_NAME = {}", install_name("NDISafe Desk"))));
        let agent = privilege_template(
            include_str!("privileges_scripts/agent.plist"),
            "NDISafe Desk",
            "com.ndisafe.desk",
        );
        assert!(agent.contains("/Applications/Ndisafe-desk.app/Contents/MacOS/Ndisafe-desk"));
        assert!(agent.contains("com.carriez.Ndisafe-desk_server"));
        assert!(agent.contains("com.ndisafe.desk"));
        assert!(!agent.contains("RustDesk"));
    }

    #[test]
    fn installation_keeps_existing_preferences_and_quotes_the_destination() {
        let script = privilege_template(
            include_str!("privileges_scripts/install.scpt"),
            "NDISafe Desk",
            "com.ndisafe.desk",
        );
        assert!(script.contains("com.carriez.NDISafe Desk/"));
        assert!(script.contains("NDISafe Desk.toml"));
        assert!(script.contains("set root_prefs_dir to quoted form of"));
        assert!(script.contains("com.carriez.Ndisafe-desk_service.plist"));
        assert!(!script.contains("com.carriez.NDISafe Desk_service.plist"));
    }

    #[test]
    fn other_product_names_are_preserved() {
        assert_eq!(install_name("RustDesk"), "RustDesk");
        assert_eq!(install_name("SupportClient"), "SupportClient");
    }
}
