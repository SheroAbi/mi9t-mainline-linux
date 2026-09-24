# boot-splash

A Plymouth boot animation for the Mi 9T, handed over cleanly to GNOME.

    sudo extras/install.sh boot-splash

Installs Plymouth, the `mi9t` theme (a spinning ring, the boot progress in
percent, "Ubuntu" and "XIAOMI MI 9T"), makes it the default theme, adds
`splash` to the boot entry on the ESP (`/boot/efi/loader/entries/ubuntu.conf`)
and a small unit that releases the splash when GDM is ready. There is no
initramfs, so Plymouth starts from systemd: the first one or two seconds
stay black, then the animation runs.

`make-splash.py` regenerates the theme's images (needs Pillow).
