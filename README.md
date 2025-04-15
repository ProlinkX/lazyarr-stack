# 😴 LazyArr-Stack: Your Semi-Automated Media Server Setup 🚀

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Required-blue?logo=docker)](https://docs.docker.com/engine/install/)
[![Docker Compose](https://img.shields.io/badge/Docker_Compose-Required-blue?logo=docker)](https://docs.docker.com/compose/install/)
[![Debian](https://img.shields.io/badge/OS-Debian_12_Preferred-orange?logo=debian)](https://www.debian.org/)

Too tired to manually configure Docker Compose files and Traefik labels *again*? Same. This script automates the tedious setup for a common media server stack (Traefik, *arrs, Jellyfin, qBittorrent, etc.).

It asks some questions (or uses defaults if you're feeling *extra* lazy), generates config files (`.env`, `docker-compose.yml`, Traefik configs), creates directories, and *tries* its best with permissions.

Think of it as a questionable shortcut. ✨

---

## ⚠️ Seriously Though, Read This First (Disclaimer & Warnings) ⚠️

> * **This script assumes you have a brain and know the basics.** It won't install Docker, configure your OS, or set up GPU drivers. That's **100% ON YOU**.
> * **Run as a regular user, NOT root.** The script uses `sudo` when necessary. Running as root is just asking for pain. Seriously, don't.
> * **Built for Debian 12.** Might work on Ubuntu/other Debian forks. Might explode. 🤷‍♂️
> * **GPU Setup = Your Job.** If you want Hardware Acceleration (NVENC/QSV/VAAPI) for Jellyfin, install drivers & configure the *host system* **BEFORE** running the script. This script only handles the Docker side.
> * **Zero Warranty Included.** If this script formats your dog or summons a configuration demon, you can't blame me. **Always review the generated `.env` and `docker-compose.yml` files before starting the stack.**

---

## ✅ Prerequisites (Stuff YOU Need Beforehand)

* **Operating System:** A working server OS. [Debian 12](https://www.debian.org/) is preferred and tested.
* **Docker Engine:** Installed and running. [🔗 Install Docker Engine](https://docs.docker.com/engine/install/)
* **Docker Compose:** Installed. [🔗 Install Docker Compose](https://docs.docker.com/compose/install/)
* **User Account:** A regular user with `sudo` access. **NOT ROOT!**
* **GPU Drivers (Optional):** Correctly installed & configured host drivers if using HW acceleration.
* **Basic Tools:** `git`, `curl`, `sudo`, `sed`, etc. (usually present on server installs).
* **Internet:** For pulling Docker images. Obviously.
* 💾 **External Storage / NAS (If Used):** If your media lives on a NAS or external drive, **you MUST mount it to your host system *before* running this script.** When the script asks for the "Media Directory" during Advanced setup, provide the **full path to the mount point** (e.g., `/mnt/movies`, `/media/nas_share`, `/srv/nfs/media`).
    > _**Note:** How to mount network shares (NFS, SMB/CIFS) or USB drives varies. Consult Linux documentation for your specific setup (e.g., editing `/etc/fstab` for persistent mounts)._ [🔗 Example: Ubuntu Mount NFS](https://ubuntu.com/server/docs/service-nfs) | [🔗 Example: Arch Wiki fstab](https://wiki.archlinux.org/title/fstab)

---

## ⚙️ How to Use This Thing

1.  **Get the Script:**
    * Clone: `git clone https://github.com/ProlinkX/lazyarr-stack.git`
    * Or download `wget https://raw.githubusercontent.com/ProlinkX/lazyarr-stack/refs/heads/main/lazyarr-setup.sh`.

2.  **Make it Executable:**
    ```bash
    chmod +x lazyarr-setup.sh
    ```

3.  **Run it (as your regular user!):**
    ```bash
    ./lazyarr-setup.sh
    ```

4.  **Answer the Questions:**
    * **Setup Mode:**
        * `Quick-start`: Uses defaults (`~/docker/mediaserver`, `~/media`), enables common apps, local HTTP access only. Fast & easy if you don't care about customization (yet). **Note:** Default media path `~/media` is likely NOT suitable if using external/NAS storage.
        * `Advanced`: Prepare for the interrogation! You'll provide:
            * `BASE_DIR`: Where configs (`.env`, `compose.yml`) live.
            * `MEDIA_DIR`: **Absolute path for media storage** (e.g., `/mnt/nas/media` - use the mount point you set up in Prerequisites!). Needs `sudo` if outside `/home`.
            * `Timezone`: e.g., `America/New_York`.
            * `Setup Type`: `DNS-Configuration-With-SSL` (needs domain/DNS setup for HTTPS) or `Local-Network-Only` (HTTP).
            * `Domain Name`: e.g., `media.example.com` or `media.local`.
            * `DNS Provider (if SSL)`: Cloudflare/DuckDNS details (API tokens entered hidden). *Ensure tokens have DNS edit permissions!*
            * `VPN Config (Optional)`: Wireguard/OpenVPN/None for Gluetun/qBittorrent (creds entered hidden).
            * `HW Acceleration (Optional)`: NVIDIA/IntelQSV/VAAPI/None for Jellyfin.
            * `Service Selection`: y/n for each app.

---

## ✨ After Running the Script (The Important Bit!) ✨

Okay, the script finished without exploding? Nice. But you're not done yet!

1.  **Navigate to Base Directory:**
    ```bash
    cd /path/to/your/base_dir # The BASE_DIR you specified
    ```

2.  **📝 REVIEW THE GENERATED CONFIGS! (Mandatory!)**
    * **`.env` file:** Open it. Check paths (especially `MEDIA_DIR`), domain, PUID/PGID, timezone. **Double-check sensitive API tokens/passwords** – special characters can sometimes mess up the `sed` replacement. Fix any mistakes!
        > 🔑 **WireGuard Users:** This script collects the basic `WIREGUARD_PRIVATE_KEY` and `WIREGUARD_ADDRESSES`. However, **some VPN providers require additional WireGuard settings** (like `WIREGUARD_PRESHARED_KEY`, `WIREGUARD_ENDPOINT_IP`, `WIREGUARD_ENDPOINT_PORT`, or specific `DOT` DNS settings).
        > You **MUST** check the Gluetun documentation for your specific VPN provider and **manually add any required extra variables** to this `.env` file before starting the stack.
        > [🔗 Gluetun VPN Provider Setup Docs (Find your provider here!)](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers)
    * **`docker-compose.yml` file:** Skim it. Understand the services, volumes (verify media volume paths!), ports, and network modes (especially if using Gluetun VPN). Verify HW accel `devices` if used.
    * **`config/traefik/` files:** Check `traefik.yml` and `dynamic/conf.yml` match your desired HTTP/HTTPS setup.

3.  **🔧 Perform Manual App Configuration (If Needed):**
    > These apps need config *files* created/edited before they'll work properly.

    * **Recyclarr:** Requires `config/recyclarr/recyclarr.yml`. You **MUST** create and configure this manually. [🔗 Recyclarr Config Guide](https://recyclarr.dev/wiki/config-reference/)
    * **Unpackerr:** Needs connection info for *arrs/qBit. Either add `UN_*` variables to `.env` (see compose file comments) OR create/edit `config/unpackerr/unpackerr.conf`. [🔗 Unpackerr Config Docs](https://unpackerr.zip/docs/configuration/)
    * **Homepage:** Configure dashboard widgets/services by editing/creating YAML files in `config/homepage/` (e.g., `services.yaml`, `widgets.yaml`). [🔗 Homepage Config Docs](https://gethomepage.dev/latest/configs/)

4.  **🚀 Start the Stack!**
    When you're happy with the configs:
    ```bash
    # Use the command the script detected (or add sudo if needed)
    docker compose up -d
    ```
    Give it a few minutes to pull images and start everything.

---

## 🔗 Post-Launch Configuration (Getting Services Talking) 🔗

Containers are running, great! Now, make them cooperate via their Web UIs.

> **General Tips:**
> * Access each service via its URL (see below).
> * Default login is often `admin`/`admin` or similar – check the service's logs or docs if unsure.
> * **CHANGE DEFAULT PASSWORDS IMMEDIATELY!**

1.  **Prowlarr (Indexer Management Hub):** ⚙️ Configure Prowlarr *first*.
    * **Add Indexers:** Log into Prowlarr -> Indexers -> Add Indexer (+) -> Choose your Torrent/Usenet indexers and configure them here. **Test each one!**
    * **Add Applications:** Settings -> Apps -> Add Application (+) -> Choose Sonarr/Radarr/Lidarr.
        * For each *arr app*, you need its **URL** and **API Key**:
            * **\*arr URL:** Use the Docker service name, e.g., `http://sonarr:8989`, `http://radarr:7878`, `http://lidarr:8686`.
            * **\*arr API Key:** Find this in Sonarr/Radarr/Lidarr under Settings -> General -> Security -> API Key.
        * Configure the "Sync Level" in Prowlarr (e.g., "Add and Remove Only").
        * **Test the connection** from Prowlarr to each *arr app*.
    * **Sync:** Prowlarr will now push the indexer configurations *to* your *arr apps*. Check the *arrs* (next step) to confirm.
    * [🔗 Prowlarr Wiki - Quick Start Guide](https://wiki.servarr.com/prowlarr/quick-start-guide#add-applications)

2.  **Sonarr / Radarr / Lidarr (*arrs):** 📺🎬🎵
    * **Verify Indexers:** Settings -> Indexers. You should see the indexers you added in Prowlarr listed here (they'll likely be tagged or named indicating they came from Prowlarr). You **do not** manually add Prowlarr *as an indexer* here.
    * **Add Download Client (qBittorrent):** Settings -> Download Clients -> Add (+) -> Choose qBittorrent.
        * **Host:** Use the Docker service name: `qbittorrent` (or `gluetun` if qBit is behind the VPN via `network_mode: service:gluetun`).
        * **Port:** Usually `8080` (the WebUI port exposed *by qBittorrent or Gluetun*).
        * **Username/Password:** The ones for qBittorrent's WebUI (change the default!).
    * **Configure Root Folders:** Settings -> Media Management -> Root Folders. Add the paths *as seen by the container*: `/tv` for Sonarr, `/movies` for Radarr, `/music` for Lidarr. These correspond to the volumes mounted in `docker-compose.yml`.
    * [🔗 Sonarr Wiki](https://wiki.servarr.com/sonarr) | [🔗 Radarr Wiki](https://wiki.servarr.com/radarr) | [🔗 Lidarr Wiki](https://wiki.servarr.com/lidarr)

3.  **Jellyseerr (Requests):** 🙋‍♂️
    * **Connect to Jellyfin:** Settings -> Services -> Jellyfin -> Add Jellyfin Server -> Enter URL (`http://jellyfin:8096`) and API Key (generate one in Jellyfin Dashboard -> API Keys).
    * **Connect to *arrs:** Settings -> Services -> Sonarr / Radarr -> Add Server -> Enter URL (`http://sonarr:8989` or `http://radarr:7878`), API Key (find in *arr's Settings -> General), and set default profiles/paths.
    * [🔗 Jellyseerr Docs](https://fallenbagel.github.io/jellyseerr/) (Similar to Overseerr docs)

4.  **qBittorrent (Downloads):** 📥
    * Log into the WebUI. **Change the default password!** (Tools -> Options -> Web UI).
    * **Configure Paths (Crucial!):** Tools -> Options -> Downloads:
        * **Default Save Path:** Set this to the *container's* path for incomplete downloads, e.g., `/downloads/incomplete`.
        * **Use Category Paths:** Enable "Keep incomplete torrents in:" and set it to `/downloads/incomplete`. Enable "Save files to location:" under "When adding a torrent" and consider enabling automatic category creation based on *arr input. The *arrs* will typically tell qBit where to save completed files (e.g., `/downloads/complete/tv/`), overriding the default *if* categories are working correctly. Ensure the final paths match what Sonarr/Radarr expect (e.g., `/downloads/complete/`).
    * Enable port forwarding in qBit settings if you configured a port in Gluetun/Compose and your VPN supports it.

5.  **Unpackerr & Recyclarr:**
    * Remember to configure them via `.env` / config files as mentioned previously, pointing them to the correct *arr URLs* and *API Keys*.

---

## 💻 Accessing Your Services

* **HTTPS Setup (Cloudflare/DuckDNS):** `https://<service_name>.<your_domain>` (e.g., `https://jellyfin.media.example.com`). Traefik dashboard: `https://traefik.<your_domain>`. (Allow time for cert generation).
* **Local Network Setup (HTTP):**
    * Use `http://<service_name>.<your_local_domain>` if you set up local DNS/hosts entries pointing the domain to your server's IP. (Docker's internal network resolves service names).
    * Otherwise, use `http://<server_ip>:<port>`. You'll need to find the correct host port mapped in the `docker-compose.yml` (especially for qBittorrent if behind Gluetun) or access via Traefik's routing (`http://traefik.<your_local_domain>` if set up).

---

## 📊 Basic Management Commands

(Run from your `BASE_DIR`)

* **View Logs:** `docker compose logs -f` (all) or `docker compose logs -f <service_name>` (specific)
* **Stop Stack:** `docker compose down`
* **Stop & Remove Volumes (DANGER! Deletes Config/Data in Volumes):** `docker compose down -v`
* **Restart:** `docker compose restart` or `docker compose down && docker compose up -d`
* **Update Images:** `docker compose pull` (pulls newer images) then `docker compose up -d` (recreates containers). (Or let Watchtower do it, maybe?)

---

❓ Good luck. Hope it works. If not, check the logs, check the docs, and maybe grab another coffee. ☕
