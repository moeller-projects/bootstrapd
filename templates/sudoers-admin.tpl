# /etc/sudoers.d/${ADMIN_USER} — installed by 20-users
# Standard passwordless sudo for the admin user with a 15-minute timestamp.

Defaults env_reset
Defaults timestamp_timeout=15
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults mail_badpass

%${ADMIN_USER} ALL=(ALL:ALL) NOPASSWD:ALL