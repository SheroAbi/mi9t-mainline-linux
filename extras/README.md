# Extras

Optional features for the Mi 9T. The normal image (`image/build-image.sh`)
installs none of them; it is the same clean Ubuntu as on the other phones of
this project, plus only what this phone's hardware needs. Install what you
want on the phone itself, from a checkout of this repository:

```bash
sudo extras/install.sh                    # list
sudo extras/install.sh boot-splash        # install one
sudo extras/install.sh boot-splash --remove
```

| Feature | What it does |
|---|---|
| [boot-splash](boot-splash/) | a Plymouth boot animation (spinning ring, progress in percent) handed over cleanly to GNOME |
