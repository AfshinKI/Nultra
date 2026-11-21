# Security

Use GitHub’s private reporting form for security issues affecting the switch, mobile apps or gateway. Include the affected component, firmware version or Git commit, expected behavior and what you observed. Remove pairing PINs, command passwords, gateway tokens and identifying device details from attachments. [Report a vulnerability privately](https://github.com/AfshinKI/Nultra/security/advisories/new)

## Existing switches

Publishing this source does not update a switch in the field. When upgrading an earlier unit, generate fresh credentials for that unit, flash the new firmware, clear its old bonds and pair the controllers again. Each generated firmware image contains the credentials for that switch. [Provisioning and upgrade instructions](firmware/README.md)

Nearby Bluetooth observers can see the advertised relay state and battery level. The gateway token grants control over every device provisioned on that gateway. Use the documented loopback listener, SSH tunnel or trusted HTTPS reverse proxy for access. [Gateway setup](web/README.md)
