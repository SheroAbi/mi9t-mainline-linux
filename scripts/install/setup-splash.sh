#!/bin/sh
# Install the Mi 9T boot splash (bootsplash/theme/) and its hand-over to GDM.
# Run as root on the phone from a checkout of this repository.
#
# There is no initramfs, so Plymouth starts from systemd
# (plymouth-start.service), after the kernel phase: the first second or two
# stay black, then the animation runs. GDM normally takes the splash over;
# mi9t-plymouth-handoff bounds the fallback if that handshake stalls.
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
SRC=$(cd "$(dirname "$0")/../../bootsplash/theme" && pwd)
T=/usr/share/plymouth/themes/mi9t

command -v plymouth >/dev/null 2>&1 || apt-get install -y -qq plymouth
install -d "$T"
install -m 644 "$SRC"/* "$T/"

cat > /etc/plymouth/plymouthd.conf <<'EOF'
[Daemon]
Theme=mi9t
ShowDelay=0
DeviceTimeout=5
EOF
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$T/mi9t.plymouth" 210
update-alternatives --set default.plymouth "$T/mi9t.plymouth"

install -d /etc/systemd/system/plymouth-start.service.d /etc/systemd/system/plymouth-quit-wait.service.d
cat > /etc/systemd/system/plymouth-start.service.d/mi9t.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/plymouthd --mode=boot --pid-file=/run/plymouth/pid --attach-to-session --tty=/dev/tty1 --ignore-serial-consoles --graphical-boot --debug-file=/var/log/mi9t-plymouth.log
TimeoutStartSec=10
TimeoutStopSec=5
SendSIGKILL=yes
EOF
cat > /etc/systemd/system/plymouth-quit-wait.service.d/mi9t.conf <<'EOF'
[Service]
TimeoutStartSec=40
EOF
cat > /usr/local/sbin/mi9t-plymouth-handoff <<'EOF'
#!/bin/sh
# GDM normally releases the splash. Bound the fallback if its handshake stalls.
if ! timeout 5 /usr/bin/plymouth quit --retain-splash; then
    systemctl kill --kill-whom=main --signal=KILL plymouth-start.service || true
fi
exit 0
EOF
chmod 755 /usr/local/sbin/mi9t-plymouth-handoff
cat > /etc/systemd/system/mi9t-plymouth-handoff.service <<'EOF'
[Unit]
Description=Release Mi 9T boot splash when GDM is ready
After=gdm.service
Before=plymouth-quit-wait.service
ConditionKernelCommandLine=splash
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mi9t-plymouth-handoff
TimeoutStartSec=8
[Install]
WantedBy=graphical.target
EOF
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/mi9t-plymouth-handoff.service
systemctl enable mi9t-plymouth-handoff.service
echo "Splash installed. The kernel command line needs 'quiet splash'."
