use super::{installer_shell, Config, ResultType};
use hbb_common::{bail, config};
use std::path::Path;

const MSI_APP_NAME: &str = "ndisafe-desk";
const MSI_INSTALL_KEY: &str =
    "HKEY_LOCAL_MACHINE\\Software\\ndisafe-desk\\InstallState\\ndisafe-desk";

pub(super) fn install_subkey() -> Option<String> {
    if crate::get_app_name() != "NDISafe Desk" {
        return None;
    }
    let location = super::get_reg_of(MSI_INSTALL_KEY, "InstallLocation");
    let is_msi = match super::get_windows_installer_state(MSI_INSTALL_KEY) {
        Ok(value) => value == Some(true),
        Err(error) => {
            hbb_common::log::warn!("Failed to read NDISafe MSI install state: {error}");
            return None;
        }
    };
    if location.is_empty() || !is_msi || !Path::new(&location).join("ndisafe-desk.exe").is_file() {
        return None;
    }
    Some(MSI_INSTALL_KEY.to_owned())
}

pub(super) fn install_app_name(subkey: &str) -> String {
    if crate::get_app_name() == "NDISafe Desk" && subkey == MSI_INSTALL_KEY {
        MSI_APP_NAME.to_owned()
    } else {
        crate::get_app_name()
    }
}

pub(super) fn service_name() -> String {
    install_subkey()
        .map(|_| MSI_APP_NAME.to_owned())
        .unwrap_or_else(crate::get_app_name)
}

pub fn init_auto_update_defaults() {
    if crate::get_app_name() == "NDISafe Desk" && !config::is_disable_installation() {
        config::DEFAULT_SETTINGS
            .write()
            .unwrap()
            .entry(config::keys::OPTION_ALLOW_AUTO_UPDATE.to_owned())
            .or_insert_with(|| "Y".to_owned());
    }
}

pub fn import_config_for_install(source: &str) -> ResultType<()> {
    if crate::get_app_name() != "NDISafe Desk" || !super::is_root() {
        bail!("Configuration import requires the NDISafe installer system account");
    }
    let source = Path::new(source);
    if !source.is_absolute() || source.extension().and_then(|s| s.to_str()) != Some("toml") {
        bail!("Invalid configuration source path");
    }
    let destination = Config::file();
    import_config_file::<Config>(source, &destination)?;
    import_config_file::<config::Config2>(
        &source.with_file_name("NDISafe Desk2.toml"),
        &destination.with_file_name("NDISafe Desk2.toml"),
    )
}

fn import_config_file<T: serde::de::DeserializeOwned>(
    source: &Path,
    destination: &Path,
) -> ResultType<()> {
    use std::{
        fs,
        io::{ErrorKind, Write},
    };

    if destination.exists() {
        return Ok(());
    }
    let data = match fs::read_to_string(source) {
        Ok(data) => data,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    let _: T = hbb_common::toml::from_str(&data)?;
    let parent = destination.parent().ok_or_else(|| {
        hbb_common::anyhow::anyhow!("The configuration destination has no parent")
    })?;
    fs::create_dir_all(parent)?;
    let mut file = match fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(destination)
    {
        Ok(file) => file,
        Err(error) if error.kind() == ErrorKind::AlreadyExists => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    file.write_all(data.as_bytes())?;
    file.sync_all()?;
    Ok(())
}

pub(super) fn update_msi(msi: &str, quiet: bool) -> ResultType<()> {
    installer_shell::validate_install_value(msi)?;
    let executable = installer_shell::get_system_executable("msiexec.exe")?;
    let mut parameters = format!("/i \"{msi}\" REBOOT=ReallySuppress /norestart");
    if quiet {
        parameters.push_str(" /qn LAUNCH_TRAY_APP=N");
    } else if !super::is_installed() {
        if config::is_disable_installation() {
            bail!("Installation is disabled");
        }
        let source = Config::file();
        let source = source.to_str().ok_or_else(|| {
            hbb_common::anyhow::anyhow!("The configuration path is not valid Unicode")
        })?;
        installer_shell::validate_install_value(source)?;
        parameters.push_str(&format!(" IMPORT_CONFIG=\"{source}\""));
    }
    // Use msiexec directly: the branded display name contains spaces and cannot
    // pass the EXE installer's intentionally restrictive batch-name validation.
    let exit_code = installer_shell::run_elevated_and_wait(&executable, &parameters, !quiet)?;
    match exit_code {
        0 | super::MSI_EXIT_SUCCESS_REBOOT_INITIATED | super::MSI_EXIT_SUCCESS_REBOOT_REQUIRED => {
            Ok(())
        }
        _ => bail!("Windows Installer failed with exit code {exit_code}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn msi_identity_is_only_used_for_its_install_state() {
        assert_eq!(install_app_name(MSI_INSTALL_KEY), "ndisafe-desk");
        assert_eq!(
            install_app_name("HKEY_LOCAL_MACHINE\\Software\\NDISafe Desk"),
            crate::get_app_name()
        );
    }

    #[test]
    fn first_install_import_preserves_existing_files_and_rejects_invalid_toml() {
        use std::fs;
        let directory =
            std::env::temp_dir().join(format!("ndisafe-import-{}", uuid::Uuid::new_v4()));
        fs::create_dir(&directory).unwrap();
        let source = directory.join("source.toml");
        let destination = directory.join("installed.toml");
        let data = "[options]\nallow-auto-update = 'N'\n";
        fs::write(&source, data).unwrap();
        import_config_file::<config::Config2>(&source, &destination).unwrap();
        assert_eq!(fs::read_to_string(&destination).unwrap(), data);
        fs::write(&source, "invalid TOML").unwrap();
        import_config_file::<config::Config2>(&source, &destination).unwrap();
        assert_eq!(fs::read_to_string(&destination).unwrap(), data);
        fs::remove_file(&destination).unwrap();
        assert!(import_config_file::<config::Config2>(&source, &destination).is_err());
        assert!(!destination.exists());
        fs::remove_dir_all(&directory).unwrap();
    }

    #[test]
    fn import_keeps_device_credentials_byte_for_byte() {
        use std::fs;
        let directory =
            std::env::temp_dir().join(format!("ndisafe-identity-{}", uuid::Uuid::new_v4()));
        fs::create_dir(&directory).unwrap();
        let source = directory.join("source.toml");
        let destination = directory.join("installed.toml");
        let data = "id = '123456789'\npassword = 'stored-password'\nsalt = 'stored-salt'\nkey_pair = [[1, 2], [3, 4]]\n";
        fs::write(&source, data).unwrap();
        import_config_file::<Config>(&source, &destination).unwrap();
        assert_eq!(fs::read_to_string(&destination).unwrap(), data);
        fs::remove_dir_all(&directory).unwrap();
    }

    #[test]
    fn automatic_update_default_does_not_override_managed_defaults() {
        let key = config::keys::OPTION_ALLOW_AUTO_UPDATE.to_owned();
        let previous = config::DEFAULT_SETTINGS.write().unwrap().remove(&key);
        init_auto_update_defaults();
        assert_eq!(
            config::DEFAULT_SETTINGS
                .read()
                .unwrap()
                .get(&key)
                .map(String::as_str),
            Some("Y")
        );
        config::DEFAULT_SETTINGS
            .write()
            .unwrap()
            .insert(key.clone(), "N".to_owned());
        init_auto_update_defaults();
        assert_eq!(
            config::DEFAULT_SETTINGS
                .read()
                .unwrap()
                .get(&key)
                .map(String::as_str),
            Some("N")
        );
        let mut defaults = config::DEFAULT_SETTINGS.write().unwrap();
        defaults.remove(&key);
        if let Some(value) = previous {
            defaults.insert(key, value);
        }
    }
}
