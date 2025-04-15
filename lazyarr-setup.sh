#!/bin/bash

# Stop! Error time! If anything breaks, we're outta here. No exceptions.
set -e

# Uncomment if you like living dangerously and want errors for unset vars. Nah.
# set -u

# If one part of a pipe fails, the whole pipe dream is over.
set -o pipefail

# === Script Setup... Ugh, Boilerplate ===

# Making things pretty... or at least colourful. Because staring at monochrome is soul-crushing.
if [ -t 1 ]; then
    # Yep, colors. Fancy.
    COLORS_SUPPORTED=true
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m' # Yellow for warnings... or just to be flashy.
    NC='\033[0m' # No Color (back to boring)
else
    # No colors for you. Or maybe you're piping this somewhere? Whatever.
    COLORS_SUPPORTED=false
    GREEN=''
    BLUE=''
    RED=''
    YELLOW=''
    NC=''
fi

# Function to splash some colour. Tries not to break if your terminal is from the stone age.
color_echo() {
    local color="$1"
    local message="$2"
    if [ "$COLORS_SUPPORTED" = true ]; then
        echo -e "${color}${message}${NC}"
    else
        echo "$message"
    fi
}

# === Utility Functions Because I'm Too Lazy to Type Repetitive Stuff ===

# Mandatory nap time. Zzzzzz... Wait, just kidding. Pauses the script for a bit.
add_pause() {
    local duration=${1:-0.5} # Default snooze: half a second
    sleep "$duration"
}

# Pretends to do hard work. Shows a '...' message, waits, then says 'Done.' like it actually achieved something.
# Usage: show_processing "What I'm supposedly doing" [snooze_time] [show_done_or_nah]
show_processing() {
    local message="$1"
    local duration=${2:-0.75} # Default thinking time
    local show_done=${3:-true} # Do we celebrate mediocrity?

    printf -- "  -> %s... " "$message"
    sleep "$duration" # Simulate intense computation... or just waiting.

    if [[ "$show_done" = true ]]; then
        # Yay, it finished... something. Green means go, right?
        if [ "$COLORS_SUPPORTED" = true ]; then
            echo -e "${GREEN}Done.${NC}"
        else
            echo "Done."
        fi
    else
        # Just move to the next line. No fanfare needed.
        echo
    fi
}

# === Alright, Let's Get This Over With... ===

color_echo "$BLUE" "The LazyArr Media Server Stack Setup Thingy"
echo "----------------------------------------"
color_echo "$YELLOW" "HEADS UP:${NC} This mess creates files/folders, needs Docker & Docker Compose."
color_echo "$YELLOW" "HEADS UP:${NC} It'll probably use 'sudo' for stuff outside your cozy home dir (like media folders). Don't sue me."
color_echo "$YELLOW" "HEADS UP:${NC} Might ask for your password like an annoying bouncer.${NC}"
echo "----------------------------------------"
add_pause 1 # Dramatic pause...

# === Dependency Checks - Do You Have the Basic Junk Installed? ===
color_echo "$GREEN" "Checking if you have the necessary tools..."
add_pause 0.2
# List of commands this script kinda relies on. Hope they exist.
dependencies=("docker" "sudo" "id" "whoami" "mkdir" "chown" "chmod" "touch" "cat" "read" "dirname" "mktemp" "sed" "mv" "getent" "printf" "sleep" "date" "tput")

# Figuring out if you're using the old 'docker-compose' or the fancy new 'docker compose'. Whatever floats your boat.
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
    show_processing "Found docker-compose (v1)... probably" 0.2
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
    show_processing "Found docker compose (v2+)... I think" 0.2
else
    color_echo "$RED" "FATAL:${NC} Can't find 'docker-compose' or 'docker compose'. Seriously?"
    echo "Go install Docker and Docker Compose, then come back."
    exit 1
fi
color_echo "$GREEN" " - Okay, gonna use this command: ${DOCKER_COMPOSE_CMD}"
add_pause 0.2

# Making sure basic tools like 'docker', 'sudo', 'mkdir' exist. It's a low bar, people.
for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        color_echo "$RED" "FATAL:${NC} Missing command '$cmd'. C'mon, install it!"
        exit 1
    fi
    show_processing "Verifying command '$cmd' exists" 0.1
done
color_echo "$GREEN" "Dependencies look okay... surprisingly."
add_pause 1

# === User and Directory Stuff - Who Are You and Where Do You Keep Your Stuff? ===
show_processing "Figuring out who you are" 0.5
CURRENT_USER=$(whoami)
# Trying to guess your home directory. Good luck if it's weird.
if [[ "$CURRENT_USER" == "root" ]]; then
    USER_HOME="/root" # Living dangerously as root, huh?
else
    # Using getent 'cause it sounds fancier than assuming /home/
    USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
    if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
        color_echo "$YELLOW" "WARNING:${NC} Couldn't figure out home dir for '$CURRENT_USER'. Assuming '/home/$CURRENT_USER'. Fingers crossed."
        USER_HOME="/home/${CURRENT_USER}"
        add_pause 1
    fi
fi
USER_ID=$(id -u)
GROUP_ID=$(id -g)
echo " - User seems to be: $CURRENT_USER (UID: $USER_ID, GID: $GROUP_ID)"
echo " - Home guess: $USER_HOME"
add_pause 1

# Function to ask you a yes/no question. Please just type 'y' or 'n', my parsing skills are fragile.
prompt_yes_no() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    local response

    while true; do
        add_pause 0.2 # Tiny pause before bugging you
        printf -- "${prompt} (y/n) [${default}]: "
        read response
        response=${response:-$default} # If you just hit Enter, use the default. Lazy recognizes lazy.
        case $response in
            [Yy]* ) printf -v "$var_name" '%s' "y"; break;; # Yes! Finally.
            [Nn]* ) printf -v "$var_name" '%s' "n"; break;; # No? Okay, fine.
            * ) echo "Just 'y' or 'n', please. It's not that hard.";; # Seriously?
        esac
    done
}

# === Docker Group Check - Can You Even *Use* Docker Without Sudo? ===
echo # Moar whitespace
color_echo "$GREEN" "Checking if you're cool enough for the Docker group..."
add_pause 0.2
CURRENT_USER=$(whoami) # Let's double-check, maybe you changed your identity?
DOCKER_GROUP="docker"

# Does the docker group even exist? Basic sanity check.
show_processing "Looking for the '$DOCKER_GROUP' group" 0.5
if getent group "$DOCKER_GROUP" > /dev/null; then
    # Okay, the group exists. Are YOU in it?
    show_processing "Checking if '$CURRENT_USER' is in the '$DOCKER_GROUP' group" 0.5
    if ! groups "$CURRENT_USER" | grep -q "\b$DOCKER_GROUP\b"; then
        color_echo "$YELLOW" "User '$CURRENT_USER' is NOT in the docker group. Shocking.${NC}"
        echo "Gonna try adding you using sudo..."
        add_pause 1

        # Attempting the magic 'usermod' command...
        if ! sudo usermod -aG "$DOCKER_GROUP" "$CURRENT_USER"; then
            color_echo "$RED" "ERROR:${NC} Failed to add user to docker group. Typical."
            color_echo "$YELLOW" "You'll probably need to run Docker commands with sudo for now.${NC}"
            echo "After this script finishes (if it does), manually run: sudo usermod -aG docker $CURRENT_USER"
            echo "THEN THE REALLY ANNOYING PART: Log out and log back in."
            add_pause 1

            # Begging time...
            prompt_yes_no "Wanna continue anyway and just use sudo for Docker stuff?" "CONTINUE_WITH_SUDO" "y"
            if [[ "$CONTINUE_WITH_SUDO" != "y" ]]; then
                color_echo "$RED" "Setup aborted. Fine, be that way.${NC}"
                exit 1
            fi

            # Fine, we'll use sudo for docker compose...
            show_processing "Setting up script to use sudo for Docker like a peasant" 0.5
            if [[ "$DOCKER_COMPOSE_CMD" == "docker-compose" ]]; then
                DOCKER_COMPOSE_CMD="sudo docker-compose"
            else
                DOCKER_COMPOSE_CMD="sudo docker compose"
            fi
        else
            # Hey, it worked! Miracles happen.
            color_echo "$GREEN" "Added '$CURRENT_USER' to the docker group.${NC}"
            color_echo "$YELLOW" "IMPORTANT:${NC} You MUST log out and log back in for this to actually work properly."
            echo "For the rest of this script run, I might still need sudo for Docker."
            add_pause 1

            prompt_yes_no "Continue now (and maybe use sudo for Docker) or quit and log out/in first?" "CONTINUE_NOW" "y"
            if [[ "$CONTINUE_NOW" != "y" ]]; then
                color_echo "$YELLOW" "Okay, go log out and back in. Then run me again. See ya.${NC}"
                exit 0
            fi

            # Setting up sudo for docker compose just for this session... sigh.
            show_processing "Configuring script to use sudo for Docker for now" 0.5
            if [[ "$DOCKER_COMPOSE_CMD" == "docker-compose" ]]; then
                DOCKER_COMPOSE_CMD="sudo docker-compose"
            else
                DOCKER_COMPOSE_CMD="sudo docker compose"
            fi
        fi
    else
        # Already in the group? Good for you.
        color_echo "$GREEN" "User '$CURRENT_USER' is already in the docker group. Fancy.${NC}"
        add_pause 0.2
        # But does it actually WORK without sudo yet? Sometimes group changes need a logout/login.
        show_processing "Checking if Docker works without sudo (takes a sec)" 1.5
        if ! docker info &>/dev/null; then
            color_echo "$YELLOW" "WARNING:${NC} You're in the group, but Docker still needs sudo? Weird."
            echo "You probably need to log out and back in. It's annoying, I know."
            add_pause 1

            prompt_yes_no "Continue using sudo for Docker just for this session?" "CONTINUE_WITH_SUDO" "y"
            if [[ "$CONTINUE_WITH_SUDO" != "y" ]]; then
                color_echo "$YELLOW" "Alright, go log out/in and run me again.${NC}"
                exit 0
            fi

            # Okay, using sudo temporarily...
            show_processing "Setting up sudo for Docker for this session" 0.5
            if [[ "$DOCKER_COMPOSE_CMD" == "docker-compose" ]]; then
                DOCKER_COMPOSE_CMD="sudo docker-compose"
            else
                DOCKER_COMPOSE_CMD="sudo docker compose"
            fi
        else
             color_echo "$GREEN" "Docker access without sudo confirmed. Nice."
             add_pause 0.2
        fi
    fi
else
    # Docker group doesn't even exist? What is this system?
    color_echo "$RED" "ERROR:${NC} Docker group ('$DOCKER_GROUP') not found. Did you even install Docker right?"
    echo "Go check your Docker setup."
    exit 1
fi
add_pause 1

# Function asks for input but gives you an easy way out (a default value).
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local response

    add_pause 0.2 # Pause before asking, build the suspense... or boredom.
    printf -- "${prompt} [${default}]: "
    read response
    # If you hit enter, use the default. If you type something, use that. Magic!
    printf -v "$var_name" '%s' "${response:-$default}"
}

# Asks for secret stuff. Hides the input like a ninja. Or tries to.
prompt_sensitive() {
    local prompt="$1"
    local var_name="$2"
    local response

    add_pause 0.2
    printf -- "$prompt: "
    read -s response # The -s makes it secret squirrel mode.
    echo # Need a newline after hiding input, looks weird otherwise.
    printf -v "$var_name" '%s' "$response"
}

# Forces you to choose from a list. Like a multiple-choice test you didn't study for.
prompt_selection() {
    local prompt="$1"
    local options_string="$2" # Pass options like "Opt1 Opt2 Opt3"
    local var_name="$3"
    local choice
    local options_array=($options_string) # Bash array magic

    echo "$prompt"
    add_pause 0.2
    # This PS3 thing changes the prompt for 'select'. Fancy, huh?
    PS3="Enter the number for your choice: "
    select opt in "${options_array[@]}"; do
        # Check if you typed a valid number... please type a valid number.
        if [[ "$REPLY" =~ ^[0-9]+$ ]] && [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "${#options_array[@]}" ]; then
            printf -v "$var_name" '%s' "$opt" # Store the chosen text, not the number.
            break # Freedom!
        else
            echo "Invalid choice '$REPLY'. Pick a number from 1 to ${#options_array[@]}. Try again."
            add_pause 0.2
        fi
    done
    PS3="" # Put the prompt back to normal before it gets weird.
    add_pause 0.2
}

# === Setup Mode - Quick & Dirty or Long & Painful? ===
echo # Whitespace is important for... readability? Sure.
color_echo "$GREEN" "Choose Your Own Adventure: Setup Mode"
prompt_selection "Which path of least resistance?" "Quick-start Advanced" "SETUP_MODE"

if [[ "$SETUP_MODE" == "Quick-start" ]]; then
    color_echo "$BLUE" "--- Quick-start Mode: Let's Get This Over With ---"
    show_processing "Applying defaults that are *probably* okay" 1
    # Sensible defaults? Maybe. Lazy defaults? Definitely.
    BASE_DIR="${USER_HOME}/docker/mediaserver" # Where the docker stuff lives
    MEDIA_DIR="${USER_HOME}/media" # Where your... 'Linux ISOs'... live
    # Try to guess the timezone. If not, fallback to UTC like a robot.
    TIMEZONE="$(cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value 2>/dev/null || echo UTC)"
    DOMAIN="media.local" # Simple local domain. Don't expect magic SSL.
    VPN_TYPE="None" # No VPN hassle in quick mode.
    HW_ACCEL="None" # No fancy hardware stuff either. Keep it simple.
    DNS_PROVIDER="None" # No DNS headaches.
    SETUP_TYPE="Local-Network-Only" # Just local access. Easy peasy.

    # Default services - the usual suspects mostly enabled.
    INSTALL_JELLYFIN="y"
    INSTALL_SONARR="y"
    INSTALL_RADARR="y"
    INSTALL_LIDARR="n" # Music is too much effort sometimes.
    INSTALL_QBITTORRENT="y"
    INSTALL_PROWLARR="y"
    INSTALL_FLARESOLVERR="y" # Because Cloudflare is annoying.
    INSTALL_JELLYSEERR="y"
    INSTALL_UNPACKERR="y" # Let the computer unzip things.
    INSTALL_RECYCLARR="n" # Requires actual config effort. Nah.
    INSTALL_HOMEPAGE="y" # A dashboard is nice, I guess.
    INSTALL_WATCHTOWER="y" # Live dangerously with auto-updates.

    color_echo "$YELLOW" "Using quick-start defaults. If you hate them, edit the .env file later, Captain Picky.${NC}"
    add_pause 1
else
    color_echo "$BLUE" "--- Advanced Mode: Okay, Mr./Ms. Fancypants, Prepare for the Interrogation ---"
    add_pause 0.2
    # Okay, you asked for it... time for questions.
    color_echo "$GREEN" "\nFolder Stuff"
    add_pause 0.2
    prompt_with_default "Where should I dump the Docker stack config?" "${USER_HOME}/docker/mediastack" "BASE_DIR"
    prompt_with_default "Where do you keep your 'Linux ISOs' (absolute path)?" "/mnt/data/media" "MEDIA_DIR"

    # === Basic Config ===
    color_echo "$GREEN" "\nBoring Basics"
    add_pause 0.2
    # Try guessing timezone, but let user override.
    prompt_with_default "What timezone are you in? (e.g., America/New_York, UTC)" "$(cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value 2>/dev/null || echo UTC)" "TIMEZONE"

    # === Setup Type ===
    color_echo "$GREEN" "\nNetwork Setup: Fancy DNS or Just Local?"
    add_pause 0.2
    prompt_selection "How do you want to access this?" "DNS-Configuration-With-SSL Local-Network-Only" "SETUP_TYPE"

    if [[ "$SETUP_TYPE" == "DNS-Configuration-With-SSL" ]]; then
        # === DNS Stuff (if you want fancy HTTPS) ===
        color_echo "$GREEN" "\nDNS Headaches"
        add_pause 0.2
        prompt_selection "Which DNS provider are you torturing yourself with?" "Cloudflare DuckDNS None" "DNS_PROVIDER"

        if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
            prompt_with_default "Your domain name (e.g., media.example.com)" "media.example.com" "DOMAIN"
            color_echo "$YELLOW" "REMINDER:${NC} Make sure your Cloudflare API Token can edit DNS for '${DOMAIN}'. No, I won't check for you."
            add_pause 0.2
            prompt_with_default "Cloudflare account email" "your-email@domain.com" "CF_EMAIL"
            prompt_sensitive "Cloudflare API token (NOT the Global Key, the specific token!)" "CF_API_TOKEN"
        elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
            prompt_with_default "Your DuckDNS domain" "yourdomain.duckdns.org" "DOMAIN"
            prompt_sensitive "Your DuckDNS token" "DUCKDNS_TOKEN"
        else
            # Chose "None" even in DNS mode? Okay... local it is.
            prompt_with_default "Enter a local domain name (e.g., media.local)" "media.local" "DOMAIN"
            color_echo "$YELLOW" "Using direct IP or maybe local DNS. Traefik won't bother with HTTPS certs.${NC}"
            DNS_PROVIDER="None" # Make sure it's really None.
            add_pause 1
        fi
    else
        # Local only setup
        prompt_with_default "Enter a local domain name (e.g., media.local)" "media.local" "DOMAIN"
        color_echo "$YELLOW" "Local network only. Access via http://<server-ip>:<port> or maybe http://<service>.<domain> if your local DNS isn't garbage.${NC}"
        DNS_PROVIDER="None"
        add_pause 1
    fi

    # === VPN Configuration (Feeling Paranoid?) ===
    color_echo "$GREEN" "\nVPN for... Reasons?"
    add_pause 0.2
    prompt_selection "Pick VPN type for Gluetun (affects qBittorrent mainly):" "Wireguard OpenVPN None" "VPN_TYPE"

    VPN_SERVICE_PROVIDER=""
    # Wipe potential vars clean first. Hygiene!
    WIREGUARD_PRIVATE_KEY=""
    WIREGUARD_ADDRESSES=""
    OPENVPN_USER=""
    OPENVPN_PASSWORD=""

    if [[ "$VPN_TYPE" == "Wireguard" ]]; then
        prompt_with_default "VPN Provider Name (see Gluetun docs, e.g., mullvad, protonvpn)" "mullvad" "VPN_SERVICE_PROVIDER"
        prompt_sensitive "Wireguard Private Key" "WIREGUARD_PRIVATE_KEY"
        prompt_with_default "Wireguard Addresses (e.g., 10.64.0.2/32)" "" "WIREGUARD_ADDRESSES"
    elif [[ "$VPN_TYPE" == "OpenVPN" ]]; then
        prompt_with_default "VPN Provider Name (see Gluetun docs, e.g., mullvad, pia)" "mullvad" "VPN_SERVICE_PROVIDER"
        prompt_sensitive "OpenVPN Username" "OPENVPN_USER"
        prompt_sensitive "OpenVPN Password" "OPENVPN_PASSWORD"
    elif [[ "$VPN_TYPE" == "None" ]]; then
        color_echo "$YELLOW" "Skipping VPN. qBittorrent will be running naked. Your funeral.${NC}"
        add_pause 1
    else
        color_echo "$RED" "ERROR: Invalid VPN type. How did you even manage that?${NC}"
        exit 1
    fi

    # === Hardware Acceleration (Does your PC have muscles?) ===
    color_echo "$GREEN" "\nHardware Acceleration for Jellyfin (Optional Performance Boost)"
    add_pause 0.2
    show_processing "Peeking at your hardware... might take a sec" 1.5

    # Try to guess what hardware you have. Might be wrong. Probably is.
    DETECTED_HW_ACCEL="None"
    RECOMMENDATION=""
    if command -v nvidia-smi &> /dev/null; then
        DETECTED_HW_ACCEL="NVIDIA"
        RECOMMENDATION=" (Detected NVIDIA, might work)"
        echo " - Found NVIDIA GPU bits."
    elif [ -e "/dev/dri/renderD128" ]; then # This magic file often means Intel/AMD GPU
        echo " - Found /dev/dri thingy."
        # Need lspci to guess better between Intel/AMD
        if command -v lspci &> /dev/null; then
            if lspci | grep -iq 'intel.*graphics'; then
                DETECTED_HW_ACCEL="IntelQSV"
                RECOMMENDATION=" (Detected Intel, QSV recommended)"
                 echo " - Looks like Intel Graphics (QSV maybe?)."
            elif lspci | grep -iq 'amd.*graphics\|advanced micro devices.*vga'; then
                DETECTED_HW_ACCEL="VAAPI"
                RECOMMENDATION=" (Detected AMD, VAAPI recommended)"
                 echo " - Looks like AMD Graphics (VAAPI maybe?)."
           else
                # Found /dev/dri but no Intel/AMD? Weird. Guess VAAPI.
                DETECTED_HW_ACCEL="VAAPI"
                RECOMMENDATION=" (Found /dev/dri, VAAPI is a common guess)"
                echo " - Found /dev/dri, no obvious Intel/AMD via lspci. VAAPI maybe?"
            fi
        else
             # No lspci, but /dev/dri exists? Defaulting to VAAPI guess.
             DETECTED_HW_ACCEL="VAAPI"
             RECOMMENDATION=" (Found /dev/dri, VAAPI is a guess)"
             echo " - Found /dev/dri, but no lspci to guess better. Assuming VAAPI."
        fi
        add_pause 0.2
    else
        echo " - No obvious hardware acceleration detected. CPU it is!"
        add_pause 0.2
    fi

    prompt_selection "Choose Hardware Acceleration for Jellyfin${RECOMMENDATION}:" "NVIDIA IntelQSV VAAPI None" "HW_ACCEL_CHOICE"
    HW_ACCEL="${HW_ACCEL_CHOICE}"

    # === Service Selection - Pick Your Poison ===
    color_echo "$GREEN" "\nWhich Apps Do You Actually Want?"
    add_pause 0.2
    echo "Say 'y' or 'n' for each. Try to keep up."
    add_pause 0.2

    prompt_yes_no "Install Jellyfin (to watch... stuff)?" "INSTALL_JELLYFIN" "y"
    prompt_yes_no "Install Sonarr (for TV... stuff)?" "INSTALL_SONARR" "y"
    prompt_yes_no "Install Radarr (for movie... stuff)?" "INSTALL_RADARR" "y"
    prompt_yes_no "Install Lidarr (for music... stuff)?" "INSTALL_LIDARR" "n"
    prompt_yes_no "Install qBittorrent (for downloading... stuff)?" "INSTALL_QBITTORRENT" "y"
    prompt_yes_no "Install Prowlarr (to manage indexer... stuff)?" "INSTALL_PROWLARR" "y"
    prompt_yes_no "Install FlaresolverR (to bypass Cloudflare's annoying stuff)?" "INSTALL_FLARESOLVERR" "y"
    prompt_yes_no "Install Jellyseerr (so others can request... stuff)?" "INSTALL_JELLYSEERR" "y"
    prompt_yes_no "Install Unpackerr (to automatically unzip... stuff)?" "INSTALL_UNPACKERR" "y"
    prompt_yes_no "Install Recyclarr (TRaSH sync? Requires manual config later!)" "INSTALL_RECYCLARR" "n"
    prompt_yes_no "Install Homepage (a dashboard to see all your... stuff)?" "INSTALL_HOMEPAGE" "y"
    prompt_yes_no "Install Watchtower (auto-updates? Risky but lazy!)" "INSTALL_WATCHTOWER" "y"
fi
add_pause 1 # Let the choices sink in...

# === Making Folders - Riveting Stuff ===
color_echo "$GREEN" "\nCreating the directory maze..."
add_pause 0.2
# Base config dirs, always needed? Probably.
CONFIG_DIRS=(config/traefik/dynamic)

# Figure out which other config folders we need based on your questionable choices.
show_processing "Planning the config folder structure" 0.5 false
[[ "$INSTALL_JELLYFIN" == "y" ]] && CONFIG_DIRS+=(config/jellyfin)
[[ "$INSTALL_SONARR" == "y" ]] && CONFIG_DIRS+=(config/sonarr)
[[ "$INSTALL_RADARR" == "y" ]] && CONFIG_DIRS+=(config/radarr)
[[ "$INSTALL_LIDARR" == "y" ]] && CONFIG_DIRS+=(config/lidarr)
[[ "$INSTALL_RECYCLARR" == "y" ]] && CONFIG_DIRS+=(config/recyclarr)
[[ "$INSTALL_JELLYSEERR" == "y" ]] && CONFIG_DIRS+=(config/jellyseerr)
[[ "$INSTALL_PROWLARR" == "y" ]] && CONFIG_DIRS+=(config/prowlarr)
[[ "$INSTALL_QBITTORRENT" == "y" ]] && CONFIG_DIRS+=(config/qbittorrent)
[[ "$INSTALL_FLARESOLVERR" == "y" ]] && CONFIG_DIRS+=(config/flaresolverr) # Doesn't *really* need one, but meh.
[[ "$INSTALL_UNPACKERR" == "y" ]] && CONFIG_DIRS+=(config/unpackerr)
[[ "$INSTALL_HOMEPAGE" == "y" ]] && CONFIG_DIRS+=(config/homepage)
# Only make gluetun config if qbit AND vpn are actually enabled. Logic!
[[ "$VPN_TYPE" != "None" && "$INSTALL_QBITTORRENT" == "y" ]] && CONFIG_DIRS+=(config/gluetun)

# Media subfolders - the usual suspects.
MEDIA_SUBDIRS=(movies tv music downloads/complete downloads/incomplete)

# Create the base directory for all this docker-compose mess.
show_processing "Making base directory: ${BASE_DIR}/shared" 0.5 false
# The || { ... } bit is bash for "if mkdir fails, print error and die"
mkdir -p "${BASE_DIR}/shared" || { color_echo "$RED" "ERROR:${NC} Couldn't create base directory ${BASE_DIR}/shared. Check permissions or path?"; exit 1; }
echo -e "${GREEN}Done.${NC}"

# Create all the config subdirectories. Loop de loop.
show_processing "Making config directories inside ${BASE_DIR}" 1 false
for conf_dir in "${CONFIG_DIRS[@]}"; do
    # Make sure the path isn't empty before trying to create it. Defensive programming? Or paranoia?
    if [[ -n "$conf_dir" ]]; then
        mkdir -p "${BASE_DIR}/${conf_dir}" || { color_echo "$RED" "ERROR:${NC} Failed creating config dir ${BASE_DIR}/${conf_dir}. Permissions again?"; exit 1; }
        # printf "." # Progress dots? Nah, too much effort.
        # add_pause 0.05
    fi
done
echo -e "${GREEN}Done.${NC}"

# Now for the media folders. Gotta make sure the parent exists first.
MEDIA_PARENT_DIR=$(dirname "${MEDIA_DIR}")
show_processing "Checking if parent media directory exists: ${MEDIA_PARENT_DIR}" 0.5
if [[ ! -d "$MEDIA_PARENT_DIR" ]]; then
    color_echo "$RED" "\nERROR:${NC} The parent directory for your media ('${MEDIA_PARENT_DIR}') doesn't exist. Can't build on thin air."
    echo "You probably need to create it first, e.g.: sudo mkdir -p '${MEDIA_PARENT_DIR}' && sudo chown ${USER_ID}:${GROUP_ID} '${MEDIA_PARENT_DIR}'"
    exit 1
fi

# Might need sudo for the main media dir and its children, especially if it's outside /home.
show_processing "Checking main media directory: ${MEDIA_DIR}" 0.5
NEEDS_MEDIA_PERMS_SET=false # Assume permissions are fine unless proven otherwise.
if [[ ! -d "${MEDIA_DIR}" ]]; then
    echo "Media directory doesn't exist. Attempting creation with sudo..."
    add_pause 0.2
    if sudo mkdir -p "${MEDIA_DIR}"; then
        NEEDS_MEDIA_PERMS_SET=true # We made it, so we definitely need to fix ownership later.
        color_echo "$GREEN" "Created ${MEDIA_DIR} using sudo. Magic."
    else
        color_echo "$RED" "ERROR:${NC} Failed to create ${MEDIA_DIR}. Need sudo? Path valid? Who knows."; exit 1;
    fi
else
    # It exists. But does it have the right owner? Check -O (user) and -G (group).
    if [[ ! -O "${MEDIA_DIR}" || ! -G "${MEDIA_DIR}" ]]; then
          NEEDS_MEDIA_PERMS_SET=true
          echo "Media directory exists, but owner/group looks wrong. Will try fixing permissions later."
          add_pause 0.2
    fi
fi

# Make sure the subdirectories (movies, tv, etc.) exist within the media dir.
show_processing "Creating/checking media subdirectories" 1 false
for sub_dir in "${MEDIA_SUBDIRS[@]}"; do
    if [[ ! -d "${MEDIA_DIR}/${sub_dir}" ]]; then
        # Attempting creation with sudo again...
        if sudo mkdir -p "${MEDIA_DIR}/${sub_dir}"; then
             NEEDS_MEDIA_PERMS_SET=true # If we create any sub, we need to set perms on the whole tree.
        else
             color_echo "$RED" "\nERROR:${NC} Failed creating media subdir ${MEDIA_DIR}/${sub_dir}. Sudo? Path? Gremlins?"; exit 1;
        fi
        # printf "." # More dots... nah.
        # add_pause 0.05
    fi
done
echo -e "${GREEN}Done.${NC}"
add_pause 1

# === Permission Party! (The Least Fun Part) ===
color_echo "$GREEN" "\nSetting permissions... *sigh*"
add_pause 0.2

# Setting ownership for the base docker directory. Using sudo just in case it's somewhere weird.
show_processing "Setting ownership for base directory: ${BASE_DIR} (using sudo, might take a sec)" 1.5 false
if ! sudo chown -R "${USER_ID}":"${GROUP_ID}" "${BASE_DIR}"; then
    color_echo "$RED" "\nERROR:${NC} Failed chown on ${BASE_DIR}. Permissions are the worst."
    echo "Try manually: sudo chown -R ${USER_ID}:${GROUP_ID} '${BASE_DIR}'"
    exit 1
fi
echo -e "${GREEN}Done.${NC}"

# Setting permissions (read/write/execute) for the base docker directory.
show_processing "Setting permissions for base directory: ${BASE_DIR} (sudo again)" 1 false
if ! sudo chmod -R u=rwX,g=rX,o=rX "${BASE_DIR}"; then # User: rwx, Group: rx, Other: rx
    color_echo "$RED" "\nERROR:${NC} Failed chmod on ${BASE_DIR}. Seriously, permissions..."
    echo "Try manually: sudo chmod -R u=rwX,g=rX,o=rX '${BASE_DIR}'"
    exit 1
fi
echo -e "${GREEN}Done.${NC}"

# Now, fix permissions on the media directory IF we detected a need earlier.
if [[ "$NEEDS_MEDIA_PERMS_SET" = true ]]; then
    show_processing "Setting ownership for media directory: ${MEDIA_DIR} (sudo, could be slow)" 1.5 false
    if ! sudo chown -R "${USER_ID}":"${GROUP_ID}" "${MEDIA_DIR}"; then
        color_echo "$RED" "\nERROR:${NC} Failed chown on ${MEDIA_DIR}. I give up on permissions."
        echo "Manual fix: sudo chown -R ${USER_ID}:${GROUP_ID} '${MEDIA_DIR}'"
        exit 1
    fi
    echo -e "${GREEN}Done.${NC}"

    show_processing "Setting permissions for media directory: ${MEDIA_DIR} (sudo)" 1 false
    # Give user and group read/write/execute, others just read/execute. Should be okay for Docker.
    if ! sudo chmod -R u=rwX,g=rwX,o=rX "${MEDIA_DIR}"; then
        color_echo "$RED" "\nERROR:${NC} Failed chmod on ${MEDIA_DIR}. Why are permissions so hard?"
        echo "Manual fix: sudo chmod -R u=rwX,g=rwX,o=rX '${MEDIA_DIR}'"
        exit 1
    fi
    echo -e "${GREEN}Done.${NC}"
else
    # If we didn't need to set perms, just say so.
    show_processing "Verifying media directory ownership/permissions" 0.5
    color_echo "$GREEN" "Media directory permissions looked okay. Skipping the chmod/chown dance."
    add_pause 0.2
fi
color_echo "$GREEN" "Permissions wrangled... hopefully correctly."
add_pause 1

# === Creating the All-Important .env File ===
color_echo "$GREEN" "\nCreating the super secret .env file..."
add_pause 0.2
ENV_FILE="${BASE_DIR}/.env"

# Create a template .env file with placeholders for everything we *might* need.
show_processing "Generating .env template file" 0.5 false
cat > "$ENV_FILE" << 'EOL'
# --- Basic Settings ---
PUID=
PGID=
TZ=
USERDIR=
BASE_DIR=
DOMAIN=

# --- Traefik / DNS ---
DNS_PROVIDER=
# Cloudflare specific (if used)
CLOUDFLARE_EMAIL=
CLOUDFLARE_DNS_API_TOKEN=
# DuckDNS specific (if used)
DUCKDNS_TOKEN=

# --- Media Paths (Important!) ---
MEDIA_DIR=
DOWNLOADS_DIR=
MOVIES_DIR=
TV_DIR=
MUSIC_DIR=

# --- VPN Stuff (Gluetun - only relevant if VPN enabled) ---
VPN_SERVICE_PROVIDER=
VPN_TYPE=
# Wireguard specific
WIREGUARD_PRIVATE_KEY=
WIREGUARD_ADDRESSES=
# OpenVPN specific
OPENVPN_USER=
OPENVPN_PASSWORD=

# --- Hardware Acceleration (if enabled) ---
HW_ACCEL=

# --- Other Junk ---
# Add more vars here if needed someday... probably not by me.
EOL
echo -e "${GREEN}Done.${NC}"

# Now, use the dark magic of `sed` to replace the placeholders with actual values.
show_processing "Jamming your answers into the .env file with sed sorcery" 1 false
TMP_ENV=$(mktemp) # Use a temporary file to avoid sed corrupting the original on some systems.

# Little helper function to escape characters that break sed. Backslashes, ampersands, and pipes are the usual suspects.
escape_sed() {
    echo "$1" | sed -e 's/\\/\\\\/g' -e 's/[&|]/\\&/g'
}

# Apply substitutions line by line. Using | as the sed delimiter because paths often have /.
# Using ${VAR:-""} makes sure optional variables (like VPN creds) are empty strings if not set, not just blank.
sed \
    -e "s|^PUID=.*$|PUID=${USER_ID}|" \
    -e "s|^PGID=.*$|PGID=${GROUP_ID}|" \
    -e "s|^TZ=.*$|TZ=$(escape_sed "${TIMEZONE}")|" \
    -e "s|^USERDIR=.*$|USERDIR=$(escape_sed "${USER_HOME}")|" \
    -e "s|^BASE_DIR=.*$|BASE_DIR=$(escape_sed "${BASE_DIR}")|" \
    -e "s|^DOMAIN=.*$|DOMAIN=$(escape_sed "${DOMAIN}")|" \
    -e "s|^DNS_PROVIDER=.*$|DNS_PROVIDER=$(escape_sed "${DNS_PROVIDER}")|" \
    -e "s|^CLOUDFLARE_EMAIL=.*$|CLOUDFLARE_EMAIL=$(escape_sed "${CF_EMAIL:-""}")|" \
    -e "s|^CLOUDFLARE_DNS_API_TOKEN=.*$|CLOUDFLARE_DNS_API_TOKEN=$(escape_sed "${CF_API_TOKEN:-""}")|" \
    -e "s|^DUCKDNS_TOKEN=.*$|DUCKDNS_TOKEN=$(escape_sed "${DUCKDNS_TOKEN:-""}")|" \
    -e "s|^MEDIA_DIR=.*$|MEDIA_DIR=$(escape_sed "${MEDIA_DIR}")|" \
    -e "s|^DOWNLOADS_DIR=.*$|DOWNLOADS_DIR=$(escape_sed "${MEDIA_DIR}")/downloads|" \
    -e "s|^MOVIES_DIR=.*$|MOVIES_DIR=$(escape_sed "${MEDIA_DIR}")/movies|" \
    -e "s|^TV_DIR=.*$|TV_DIR=$(escape_sed "${MEDIA_DIR}")/tv|" \
    -e "s|^MUSIC_DIR=.*$|MUSIC_DIR=$(escape_sed "${MEDIA_DIR}")/music|" \
    -e "s|^VPN_SERVICE_PROVIDER=.*$|VPN_SERVICE_PROVIDER=$(escape_sed "${VPN_SERVICE_PROVIDER:-""}")|" \
    -e "s|^VPN_TYPE=.*$|VPN_TYPE=$(escape_sed "${VPN_TYPE}")|" \
    -e "s|^WIREGUARD_PRIVATE_KEY=.*$|WIREGUARD_PRIVATE_KEY=$(escape_sed "${WIREGUARD_PRIVATE_KEY:-""}")|" \
    -e "s|^WIREGUARD_ADDRESSES=.*$|WIREGUARD_ADDRESSES=$(escape_sed "${WIREGUARD_ADDRESSES:-""}")|" \
    -e "s|^OPENVPN_USER=.*$|OPENVPN_USER=$(escape_sed "${OPENVPN_USER:-""}")|" \
    -e "s|^OPENVPN_PASSWORD=.*$|OPENVPN_PASSWORD=$(escape_sed "${OPENVPN_PASSWORD:-""}")|" \
    -e "s|^HW_ACCEL=.*$|HW_ACCEL=$(escape_sed "${HW_ACCEL}")|" \
    "$ENV_FILE" > "$TMP_ENV"

# Move the finished temp file back to the real .env location.
mv "$TMP_ENV" "$ENV_FILE" || { color_echo "$RED" "ERROR:${NC} Failed to move temp .env file. The filesystem gods are angry."; exit 1; }
echo -e "${GREEN}Done.${NC}"
color_echo "$YELLOW" "-----------------------------------------------------"
color_echo "$YELLOW" "WARNING:${NC} If you used crazy special characters (\`, $, \\, etc.) in passwords/tokens,"
color_echo "$YELLOW" "         manually check ${ENV_FILE} to make sure they aren't broken. Sed isn't perfect."
color_echo "$YELLOW" "-----------------------------------------------------"
add_pause 1.5

# === Traefik Config - The Gatekeeper ===
color_echo "$GREEN" "\nSetting up Traefik, the bouncer..."
add_pause 0.2
# Make sure the dynamic config dir exists (should already, but belts and suspenders...)
mkdir -p "${BASE_DIR}/config/traefik/dynamic"

# Create the main traefik.yml based on whether you chose fancy DNS or not.
if [[ "$DNS_PROVIDER" == "Cloudflare" || "$DNS_PROVIDER" == "DuckDNS" ]]; then
    show_processing "Generating traefik.yml for $DNS_PROVIDER (Fancy HTTPS mode)" 1 false
else
    show_processing "Generating traefik.yml (Basic HTTP peasant mode)" 1 false
fi

# --- traefik.yml content - depends on DNS choice ---
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
    # Cloudflare config with HTTPS redirect and Let's Encrypt via DNS challenge
    cat > "${BASE_DIR}/config/traefik/traefik.yml" << EOL
# traefik.yml (Static Config - Cloudflare Edition)
api:
  dashboard: true # Enable the fancy dashboard

entryPoints:
  web: # HTTP Entrypoint
    address: ":80"
    http:
      redirections: # Force HTTPS
        entryPoint:
          to: websecure # Redirect to the HTTPS entrypoint
          scheme: https
          permanent: true # Use 301 redirect because we're committed.
  websecure: # HTTPS Entrypoint
    address: ":443"
    http:
      tls:
        certResolver: cloudflare # Use the Let's Encrypt resolver below
        domains:
          - main: \${DOMAIN} # Your main domain (from .env)
            sans: # Also get certs for subdomains
              - "*.\${DOMAIN}" # Wildcard cert! Ooh fancy.
      middlewares: # Apply these middlewares globally to HTTPS
        - securityHeaders@file # Use the security headers defined in dynamic config

providers:
  docker: # Talk to Docker to find containers
    endpoint: "unix:///var/run/docker.sock" # Standard Docker socket path
    exposedByDefault: false # IMPORTANT: Don't expose containers unless explicitly told to via labels.
    network: traefik_proxy # Only watch containers on this network
  file: # Load dynamic config (middlewares, etc.) from files
    directory: /etc/traefik/dynamic # Path inside the Traefik container
    watch: true # Reload automatically if files change (cool!)

certificatesResolvers: # How to get SSL certs
  cloudflare:
    acme: # Let's Encrypt stuff
      email: \${CLOUDFLARE_EMAIL} # Your email (from .env)
      storage: /etc/traefik/acme.json # Where to store certs inside the container
      dnsChallenge: # Use DNS to prove ownership
        provider: cloudflare
        resolvers: # Use Cloudflare's own DNS servers for checks
          - "1.1.1.1:53"
          - "1.0.0.1:53"
        # API token is passed via environment variable in docker-compose.yml

log:
  level: INFO # How much Traefik should babble. INFO is usually fine.
accessLog: {} # Turn on access logs. Useful for debugging later.
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
    # DuckDNS config with HTTPS redirect and Let's Encrypt via DNS challenge
    cat > "${BASE_DIR}/config/traefik/traefik.yml" << EOL
# traefik.yml (Static Config - DuckDNS Edition)
api:
  dashboard: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: duckdns # Use the DuckDNS Let's Encrypt resolver
        domains:
          - main: \${DOMAIN} # Your DuckDNS domain (from .env)
      middlewares:
        - securityHeaders@file

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik_proxy
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  duckdns:
    acme:
      # DuckDNS doesn't strictly need an email, but Traefik might whine. Use a placeholder.
      email: admin@\${DOMAIN}
      storage: /etc/traefik/acme.json
      dnsChallenge:
        provider: duckdns
        resolvers:
          - "1.1.1.1:53"
          - "1.0.0.1:53"
        # DuckDNS token is passed via environment variable in docker-compose.yml

log:
  level: INFO
accessLog: {}
EOL
else
    # Local-only config (HTTP only, no Let's Encrypt)
    cat > "${BASE_DIR}/config/traefik/traefik.yml" << EOL
# traefik.yml (Static Config - Local/HTTP Peasant Edition)
api:
  dashboard: true
  insecure: true # Allow dashboard access over HTTP (still recommend auth middleware!)

entryPoints:
  web: # Only need HTTP entrypoint
    address: ":80"
    http:
      middlewares: # Still good to have security headers even on HTTP
        - securityHeaders@file

# No HTTPS entrypoint needed for local peasant mode.

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik_proxy
  file:
    directory: /etc/traefik/dynamic
    watch: true

log:
  level: INFO
accessLog: {}
EOL
fi
# --- End of traefik.yml generation ---
echo -e "${GREEN}Done.${NC}"

# Create Traefik dynamic configuration (middlewares)
show_processing "Generating Traefik dynamic config (dynamic/conf.yml - middlewares)" 0.7 false
cat > "${BASE_DIR}/config/traefik/dynamic/conf.yml" << EOL
# dynamic/conf.yml (Dynamic Configuration - Mostly Middlewares)

tls:
  options:
    default: # Default TLS settings for HTTPS (if used)
      minVersion: VersionTLS12 # Don't use ancient TLS versions
      cipherSuites: # Modernish cipher suites. Don't ask me, I copied these.
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256

http:
  middlewares:
    # --- Sensible Security Headers ---
    # Apply these globally in traefik.yml or per-service via labels.
    securityHeaders:
      headers:
        frameDeny: true # Disallow embedding in iframes
        browserXssFilter: true # Turn on basic XSS filtering in browser
        contentTypeNosniff: true # Don't let browser guess content types
        forceSTSHeader: true # Enforce HSTS (HTTPS only)
        stsIncludeSubdomains: true # HSTS for subdomains too
        stsPreload: true # Ask browsers to preload HSTS (be sure HTTPS works!)
        stsSeconds: 31536000 # HSTS for 1 year
        customFrameOptionsValue: SAMEORIGIN # Allow framing only from same origin
        # Content-Security-Policy is tricky, better to define per-service if needed.
        customRequestHeaders:
          X-Forwarded-Proto: https # Tell backend apps the original request was HTTPS

    # --- Example: Basic Auth (Uncomment and configure if needed) ---
    # To generate user:hash: echo \$(htpasswd -nb your_user your_pass) | sed -e s/\\$/\\\$\$/g
    # Apply with label: - "traefik.http.routers.myrouter.middlewares=basic-auth@file"
    # basic-auth:
    #  basicAuth:
    #    users:
    #      - "user:\$\$apr1\$\$........\$\$......................" # Replace with generated hash

EOL
echo -e "${GREEN}Done.${NC}"

# Create acme.json for Let's Encrypt if using DNS provider
if [[ "$DNS_PROVIDER" == "Cloudflare" || "$DNS_PROVIDER" == "DuckDNS" ]]; then
    show_processing "Creating empty acme.json for Let's Encrypt certs" 0.5 false
    touch "${BASE_DIR}/config/traefik/acme.json"
    chmod 600 "${BASE_DIR}/config/traefik/acme.json" # Make it private, contains certs!
    echo -e "${GREEN}Done.${NC}"
fi
add_pause 1

# === Creating docker-compose.yml - The Grand Finale ===
color_echo "$GREEN" "\nGenerating the docker-compose.yml... The orchestrator of chaos."
add_pause 0.2

DOCKER_COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
# Start with a clean slate. Zap the old file if it exists.
> "$DOCKER_COMPOSE_FILE"

# Show one message for the whole file generation, it's long.
show_processing "Assembling the docker-compose.yml monstrosity" 2.5 false

# --- Write Header and Networks ---
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
# docker-compose.yml
# Generated by the LazyArr-Stack script. Blame it, not me.
# Consider pinning image versions (e.g., :vX.Y.Z instead of :latest) if you hate surprises.
version: '3.8' # Using a reasonably modern version

networks:
  traefik_proxy: # Network for Traefik to see other containers
    driver: bridge
    name: traefik_proxy # Give it a predictable name
  # Note: If using Gluetun (VPN), containers connect via 'network_mode: service:gluetun'
  # They won't be directly on traefik_proxy unless explicitly added.

services:
EOL

# --- Traefik Service (The Bouncer/Router) ---
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
  traefik:
    image: traefik:latest # Use the latest Traefik... maybe pin this later?
    container_name: traefik
    restart: unless-stopped # Keep it running unless you manually stop it.
    security_opt: # Some basic security hardening
      - no-new-privileges:true
    ports: # Ports exposed on the HOST machine
      - "80:80"  # HTTP entrypoint
EOL
# Add port 443 only if using HTTPS via DNS provider
if [[ "$DNS_PROVIDER" == "Cloudflare" || "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "443:443" # HTTPS entrypoint (only needed if using Cloudflare/DuckDNS)
EOL
fi
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      # - "8080:8080" # Optional: Expose Traefik dashboard directly (if api.insecure=true) - Use Host rule instead!
    networks:
      - traefik_proxy # Traefik needs to be on its own network to see others
    environment: # Environment variables for Traefik container
      - TZ=${TZ} # Pass timezone from .env
EOL
# Add DNS provider API credentials if needed
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      # Cloudflare API creds (read from .env)
      - CLOUDFLARE_EMAIL=${CLOUDFLARE_EMAIL}
      - CLOUDFLARE_DNS_API_TOKEN=${CLOUDFLARE_DNS_API_TOKEN}
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      # DuckDNS Token (read from .env)
      - DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
EOL
fi
# Add volumes and labels for Traefik
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
    volumes: # Mount files/folders into the container
      - /var/run/docker.sock:/var/run/docker.sock:ro # Access Docker socket (read-only) to discover containers
      - ./config/traefik/traefik.yml:/etc/traefik/traefik.yml:ro # Mount static config (read-only)
      - ./config/traefik/dynamic:/etc/traefik/dynamic:ro # Mount dynamic config (read-only)
EOL
# Mount acme.json only if using DNS provider for HTTPS
if [[ "$DNS_PROVIDER" == "Cloudflare" || "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - ./config/traefik/acme.json:/etc/traefik/acme.json # Mount Let's Encrypt storage (needs write access)
EOL
fi
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
    labels: # Labels for Traefik to configure itself
      # --- Traefik Dashboard Routing ---
      - "traefik.enable=true" # Tell Traefik to manage this container
      # Route requests for traefik.your.domain to the internal API service
      - "traefik.http.routers.traefik-dashboard.rule=Host(`traefik.${DOMAIN}`)" # Use Host rule with domain from .env
      - "traefik.http.routers.traefik-dashboard.service=api@internal" # Target the special internal API service
EOL
# Add entrypoint and TLS labels based on DNS provider
if [[ "$DNS_PROVIDER" == "None" ]]; then
# Local HTTP setup
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      # Use HTTP entrypoint for local access
      - "traefik.http.routers.traefik-dashboard.entrypoints=web"
      # Recommend adding basic auth middleware even locally! Uncomment in dynamic/conf.yml and add label here:
      # - "traefik.http.routers.traefik-dashboard.middlewares=basic-auth@file"
EOL
else
# HTTPS setup
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      # Use HTTPS entrypoint for secure access
      - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
      # Enable TLS and specify the certificate resolver
EOL
fi
# Add the correct cert resolver label based on DNS provider
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.traefik-dashboard.tls.certresolver=cloudflare"
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.traefik-dashboard.tls.certresolver=duckdns"
EOL
fi

# --- Gluetun Service (VPN Tunnel - Only if needed) ---
if [[ "$VPN_TYPE" != "None" && "$INSTALL_QBITTORRENT" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  gluetun: # The VPN tunnel master
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    restart: unless-stopped
    cap_add:
      - NET_ADMIN # Needs special network powers to create the tunnel
    devices: # Sometimes needed for Wireguard to work right
      - /dev/net/tun:/dev/net/tun
    ports: # IMPORTANT: Expose ports for VPN'd services HERE, not on the service itself!
      # Example: qBittorrent Web UI (default 8080)
      - "8080:8080" # Map host 8080 to Gluetun's 8080 (where qBit will listen)
      # Example: qBittorrent incoming connection port (must match qBit settings AND be forwarded by VPN provider!)
      # - "6881:6881" # TCP
      # - "6881:6881/udp" # UDP
    volumes:
      - ./config/gluetun:/gluetun # Persist Gluetun's config/state
    environment:
      - TZ=${TZ}
      # --- Core VPN Settings (from .env) ---
      - VPN_SERVICE_PROVIDER=${VPN_SERVICE_PROVIDER}
      - VPN_TYPE=${VPN_TYPE}
      # --- OpenVPN Credentials (only used if VPN_TYPE=openvpn) ---
      - OPENVPN_USER=${OPENVPN_USER:-""}
      - OPENVPN_PASSWORD=${OPENVPN_PASSWORD:-""}
      # --- Wireguard Credentials (only used if VPN_TYPE=wireguard) ---
      - WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY:-""}
      - WIREGUARD_ADDRESSES=${WIREGUARD_ADDRESSES:-""}
      # --- Other Gluetun Options ---
      - DOT=off # Disable DNS over TLS if you like, check Gluetun docs
      - UPDATER_PERIOD=24h # Check for VPN server updates daily
EOL
fi # End of Gluetun

# --- Jellyfin Service (For watching... stuff) ---
if [[ "$INSTALL_JELLYFIN" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  jellyfin:
    image: lscr.io/linuxserver/jellyfin:latest # LinuxServer.io image is usually solid
    container_name: jellyfin
    restart: unless-stopped
    networks:
      - traefik_proxy # Needs to be reachable by Traefik
    environment:
      - PUID=${PUID} # User ID from .env
      - PGID=${PGID} # Group ID from .env
      - TZ=${TZ} # Timezone
      # Tell Jellyfin its external URL (auto http/https based on DNS choice)
      - JELLYFIN_PublishedServerUrl=http${DNS_PROVIDER:+#s}://${DOMAIN}
EOL
# Add hardware acceleration stuff if selected
case "$HW_ACCEL" in
  NVIDIA)
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      # --- NVIDIA Hardware Acceleration ---
      - NVIDIA_VISIBLE_DEVICES=all # Make GPUs visible
    deploy: # Docker swarm style deployment config (also works in compose v2+)
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all # Use all available GPUs
              capabilities: [gpu] # Request GPU capabilities
EOL
    ;;
  IntelQSV|VAAPI)
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      # --- Intel QSV / AMD VAAPI Hardware Acceleration ---
    devices: # Pass the DRI device node into the container
      - /dev/dri:/dev/dri
EOL
    ;;
esac
# Common Jellyfin volumes and labels
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
    volumes:
      - ./config/jellyfin:/config # Jellyfin config folder
      - ./shared:/shared # Optional shared space
      # Mount media folders (read-only recommended unless Jellyfin needs to write metadata?)
      - ${TV_DIR}:/data/tvshows:ro
      - ${MOVIES_DIR}:/data/movies:ro
      - ${MUSIC_DIR}:/data/music:ro
      # - ./cache/jellyfin:/cache # Optional separate cache volume
    labels: # Traefik labels
      - "traefik.enable=true" # Let Traefik manage this service
      - "traefik.http.routers.jellyfin.rule=Host(`jellyfin.${DOMAIN}`)" # Route jellyfin.your.domain
      - "traefik.http.services.jellyfin.loadbalancer.server.port=8096" # Tell Traefik the backend port
      - "traefik.http.routers.jellyfin.service=jellyfin" # Link router to this service
EOL
# Add entrypoint and TLS labels based on DNS provider
if [[ "$DNS_PROVIDER" == "None" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.jellyfin.entrypoints=web" # Use HTTP
EOL
else
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.jellyfin.entrypoints=websecure" # Use HTTPS
EOL
fi
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.jellyfin.tls.certresolver=cloudflare" # Use Cloudflare for certs
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.jellyfin.tls.certresolver=duckdns" # Use DuckDNS for certs
EOL
fi
fi # End of Jellyfin

# --- Sonarr Service (TV Show Automator) ---
if [[ "$INSTALL_SONARR" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    restart: unless-stopped
    networks:
      - traefik_proxy
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/sonarr:/config # Sonarr config
      - ${TV_DIR}:/tv # Map TV shows folder
      - ${DOWNLOADS_DIR}:/downloads # Map downloads folder (where qBit drops stuff)
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.sonarr.rule=Host(`sonarr.${DOMAIN}`)" # sonarr.your.domain
      - "traefik.http.services.sonarr.loadbalancer.server.port=8989" # Sonarr's backend port
      - "traefik.http.routers.sonarr.service=sonarr"
EOL
# Add entrypoint and TLS labels
if [[ "$DNS_PROVIDER" == "None" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.sonarr.entrypoints=web"
EOL
else
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.sonarr.entrypoints=websecure"
EOL
fi
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.sonarr.tls.certresolver=cloudflare"
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.sonarr.tls.certresolver=duckdns"
EOL
fi
fi # End of Sonarr

# --- Radarr Service (Movie Automator) ---
if [[ "$INSTALL_RADARR" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    restart: unless-stopped
    networks:
      - traefik_proxy
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/radarr:/config # Radarr config
      - ${MOVIES_DIR}:/movies # Map movies folder
      - ${DOWNLOADS_DIR}:/downloads # Map downloads folder
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.radarr.rule=Host(`radarr.${DOMAIN}`)" # radarr.your.domain
      - "traefik.http.services.radarr.loadbalancer.server.port=7878" # Radarr's backend port
      - "traefik.http.routers.radarr.service=radarr"
EOL
# Add entrypoint and TLS labels
if [[ "$DNS_PROVIDER" == "None" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.radarr.entrypoints=web"
EOL
else
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.radarr.entrypoints=websecure"
EOL
fi
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.radarr.tls.certresolver=cloudflare"
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.radarr.tls.certresolver=duckdns"
EOL
fi
fi # End of Radarr

# --- Lidarr Service (Music Automator) ---
if [[ "$INSTALL_LIDARR" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  lidarr:
    image: lscr.io/linuxserver/lidarr:latest
    container_name: lidarr
    restart: unless-stopped
    networks:
      - traefik_proxy
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/lidarr:/config # Lidarr config
      - ${MUSIC_DIR}:/music # Map music folder
      - ${DOWNLOADS_DIR}:/downloads # Map downloads folder
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.lidarr.rule=Host(`lidarr.${DOMAIN}`)" # lidarr.your.domain
      - "traefik.http.services.lidarr.loadbalancer.server.port=8686" # Lidarr's backend port
      - "traefik.http.routers.lidarr.service=lidarr"
EOL
# Add entrypoint and TLS labels
if [[ "$DNS_PROVIDER" == "None" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.lidarr.entrypoints=web"
EOL
else
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.lidarr.entrypoints=websecure"
EOL
fi
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.lidarr.tls.certresolver=cloudflare"
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.lidarr.tls.certresolver=duckdns"
EOL
fi
fi # End of Lidarr

# --- Prowlarr Service (Indexer Manager) ---
if [[ "$INSTALL_PROWLARR" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    restart: unless-stopped
    networks:
      - traefik_proxy
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/prowlarr:/config # Prowlarr config
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prowlarr.rule=Host(`prowlarr.${DOMAIN}`)" # prowlarr.your.domain
      - "traefik.http.services.prowlarr.loadbalancer.server.port=9696" # Prowlarr's backend port
      - "traefik.http.routers.prowlarr.service=prowlarr"
EOL
# Add entrypoint and TLS labels
if [[ "$DNS_PROVIDER" == "None" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.prowlarr.entrypoints=web"
EOL
else
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.prowlarr.entrypoints=websecure"
EOL
fi
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.prowlarr.tls.certresolver=cloudflare"
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.prowlarr.tls.certresolver=duckdns"
EOL
fi
fi # End of Prowlarr

# --- qBittorrent Service (Downloader) ---
if [[ "$INSTALL_QBITTORRENT" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
EOL
# Conditional networking: Use Gluetun's network if VPN is enabled, otherwise use Traefik's network.
if [[ "$VPN_TYPE" != "None" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
    network_mode: "service:gluetun" # Route all traffic through Gluetun container
    depends_on: # Don't start qBit until Gluetun is (supposedly) ready
      gluetun:
        condition: service_started # Might need 'service_healthy' if Gluetun supports healthchecks
EOL
else
# No VPN, connect directly to Traefik network
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
    networks:
      - traefik_proxy
EOL
fi
# Common qBittorrent config
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - WEBUI_PORT=8080 # The port qBit listens on INSIDE the container (or Gluetun's network)
    volumes:
      - ./config/qbittorrent:/config # qBit config
      - ${DOWNLOADS_DIR}:/downloads # Map downloads folder (needs R/W access!)
    labels: # Traefik labels (needed even if behind VPN, Traefik routes to Gluetun's exposed port)
      - "traefik.enable=true"
      - "traefik.http.routers.qbittorrent.rule=Host(`qbittorrent.${DOMAIN}`)" # qbittorrent.your.domain
      # Tell Traefik the backend port (which is exposed on Gluetun if VPN is used, or qBit directly if not)
      - "traefik.http.services.qbittorrent.loadbalancer.server.port=8080"
      - "traefik.http.routers.qbittorrent.service=qbittorrent"
      # Highly recommended to add authentication! Uncomment basic-auth in dynamic/conf.yml and add label:
      # - "traefik.http.routers.qbittorrent.middlewares=basic-auth@file"
EOL
# Add entrypoint and TLS labels
if [[ "$DNS_PROVIDER" == "None" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.qbittorrent.entrypoints=web"
EOL
else
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.qbittorrent.entrypoints=websecure"
EOL
fi
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.qbittorrent.tls.certresolver=cloudflare"
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.qbittorrent.tls.certresolver=duckdns"
EOL
fi
fi # End of qBittorrent

# --- Flaresolverr Service (Cloudflare Annoyance Bypass) ---
if [[ "$INSTALL_FLARESOLVERR" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  flaresolverr:
    image: flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    restart: unless-stopped
    # Needs network access, but doesn't need to be exposed via Traefik usually.
    # Put it on traefik_proxy so Prowlarr/etc can reach it at http://flaresolverr:8191
    networks:
      - traefik_proxy
    environment:
      - LOG_LEVEL=info # Keep logs reasonable
      - LOG_HTML=false # Don't log giant HTML pages
      - CAPTCHA_SOLVER=none # Set up a solver if you have one (e.g., hcaptcha)
      - TZ=${TZ}
    # No volumes needed unless you have specific config needs.
    # No ports exposed to host.
    # No Traefik labels needed.
EOL
fi # End of Flaresolverr

# --- Jellyseerr Service (Request System) ---
if [[ "$INSTALL_JELLYSEERR" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  jellyseerr:
    image: fallenbagel/jellyseerr:latest # The cool Overseerr fork for Jellyfin/Emby
    container_name: jellyseerr
    restart: unless-stopped
    networks:
      - traefik_proxy
    environment:
      - LOG_LEVEL=info
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/jellyseerr:/app/config # Jellyseerr config
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.jellyseerr.rule=Host(`jellyseerr.${DOMAIN}`)" # jellyseerr.your.domain
      - "traefik.http.services.jellyseerr.loadbalancer.server.port=5055" # Jellyseerr's backend port
      - "traefik.http.routers.jellyseerr.service=jellyseerr"
EOL
# Add entrypoint and TLS labels
if [[ "$DNS_PROVIDER" == "None" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.jellyseerr.entrypoints=web"
EOL
else
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.jellyseerr.entrypoints=websecure"
EOL
fi
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.jellyseerr.tls.certresolver=cloudflare"
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.jellyseerr.tls.certresolver=duckdns"
EOL
fi
fi # End of Jellyseerr

# --- Unpackerr Service (Automatic Extraction) ---
if [[ "$INSTALL_UNPACKERR" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  unpackerr:
    image: golift/unpackerr:latest
    container_name: unpackerr
    restart: unless-stopped
    # Needs network access to talk to Sonarr/Radarr APIs
    networks:
      - traefik_proxy
    environment:
      - PUID=${PUID} # Needs correct perms to read/write/delete downloads
      - PGID=${PGID}
      - TZ=${TZ}
      # Configuration is done via environment variables OR a config file
      # See Unpackerr docs: https://unpackerr.zip/docs/configuration/
      # Example Env Vars (set in .env or here):
      # - UN_SONARR_0_URL=http://sonarr:8989
      # - UN_SONARR_0_API_KEY=YOUR_SONARR_API_KEY
      # - UN_RADARR_0_URL=http://radarr:7878
      # - UN_RADARR_0_API_KEY=YOUR_RADARR_API_KEY
      # - UN_QBITTORRENT_0_URL=http://qbittorrent:8080 # Or Gluetun's if VPN'd
      # - UN_QBITTORRENT_0_USER=admin
      # - UN_QBITTORRENT_0_PASS=adminadmin
    volumes:
      # Mount config file if you prefer that over env vars
      # - ./config/unpackerr:/config # unpackerr.conf goes here
      # Needs R/W access to the downloads folder to extract and clean up
      - ${DOWNLOADS_DIR}:/downloads
    # Optional: Make sure *arrs and qBit are running first
    # depends_on:
    #   - sonarr
    #   - radarr
    #   - qbittorrent
EOL
fi # End of Unpackerr

# --- Recyclarr Service (TRaSH Guide Sync) ---
if [[ "$INSTALL_RECYCLARR" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  recyclarr:
    image: ghcr.io/recyclarr/recyclarr:latest
    container_name: recyclarr
    restart: unless-stopped
    # Needs network access to talk to Sonarr/Radarr
    networks:
      - traefik_proxy
    environment:
      - TZ=${TZ}
      # PUID/PGID usually not needed unless writing files, which it shouldn't be.
    volumes:
      # IMPORTANT: You NEED to create recyclarr.yml in this config folder!
      - ./config/recyclarr:/config
    # command: sync # Uncomment to run once and exit, instead of cron schedule
    # Optional: Depends on Sonarr/Radarr
    # depends_on:
    #   - sonarr
    #   - radarr
EOL
fi # End of Recyclarr

# --- Homepage Service (Dashboard) ---
if [[ "$INSTALL_HOMEPAGE" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  homepage:
    image: ghcr.io/gethomepage/homepage:latest # The popular dashboard app
    container_name: homepage
    restart: unless-stopped
    networks:
      - traefik_proxy
    environment:
      - PUID=${PUID} # For config file ownership
      - PGID=${PGID}
      - TZ=${TZ}
      # Homepage config is done via YAML files in the config volume
    volumes:
      # Mount the config directory where you'll put services.yaml, widgets.yaml etc.
      - ./config/homepage:/app/config
      # Mount Docker socket (read-only) for Docker integration widgets
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - "traefik.enable=true"
      # Route homepage.your.domain (or just your.domain if you change the rule)
      - "traefik.http.routers.homepage.rule=Host(`homepage.${DOMAIN}`)"
      - "traefik.http.services.homepage.loadbalancer.server.port=3000" # Homepage's backend port
      - "traefik.http.routers.homepage.service=homepage"
EOL
# Add entrypoint and TLS labels
if [[ "$DNS_PROVIDER" == "None" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.homepage.entrypoints=web"
EOL
else
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.homepage.entrypoints=websecure"
EOL
fi
if [[ "$DNS_PROVIDER" == "Cloudflare" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.homepage.tls.certresolver=cloudflare"
EOL
elif [[ "$DNS_PROVIDER" == "DuckDNS" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'
      - "traefik.http.routers.homepage.tls.certresolver=duckdns"
EOL
fi
fi # End of Homepage

# --- Watchtower Service (Auto Updater - Use With Caution!) ---
if [[ "$INSTALL_WATCHTOWER" == "y" ]]; then
cat >> "$DOCKER_COMPOSE_FILE" << 'EOL'

  watchtower: # Automatically updates other containers. Can break things!
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    environment:
      - TZ=${TZ}
      # --- Watchtower Configuration ---
      # - WATCHTOWER_CLEANUP=true # Remove old images after update
      # - WATCHTOWER_MONITOR_ONLY=false # Set to 'false' to actually PERFORM updates! Default is 'true' (report only)
      # - WATCHTOWER_SCHEDULE="0 0 4 * * *" # Cron schedule (e.g., 4 AM daily) - Default is random interval
      # - WATCHTOWER_TIMEOUT=30s # How long to wait for container stop signal
      # Add notification configs here if desired (Slack, Discord, etc.)
    volumes:
      # Needs Docker socket access to manage containers
      - /var/run/docker.sock:/var/run/docker.sock:ro # Read-only is safer if just monitoring
      # If actually updating (MONITOR_ONLY=false), might need RW access:
      # - /var/run/docker.sock:/var/run/docker.sock
    # Default command: Check every 5 mins, monitor only, no cleanup. Override below.
    # Example: Check hourly, cleanup old images, actually perform updates:
    # command: --cleanup --interval 3600 --monitor-only false
    command: --cleanup --interval 86400 --monitor-only true # Check daily, cleanup, but only report (safe default)
EOL
fi # End of Watchtower

# --- End of docker-compose.yml Generation ---
echo -e "${GREEN}Done.${NC}" # Finally done writing that monster file.
color_echo "$GREEN" "docker-compose.yml created at ${DOCKER_COMPOSE_FILE}. Go take a look maybe.${NC}"
add_pause 1

# === Final Instructions - AKA "Now What?" ===
echo # Whitespace... breathe...
echo "----------------------------------------"
color_echo "$GREEN" "Setup Complete! (Maybe. Probably.)"
echo "----------------------------------------"
add_pause 1
echo "All the config junk got dumped in: $(color_echo "$BLUE" "${BASE_DIR}")"
echo ""
color_echo "$YELLOW" "IMPORTANT - READ THIS OR CRY LATER:"
add_pause 0.2
echo "1. $(color_echo "$YELLOW" "Sanity Check:")"
echo "   - Go LOOK at the $(color_echo "$BLUE" "${BASE_DIR}/.env") file. Make sure passwords/tokens/paths aren't garbage."
echo "   - Skim the $(color_echo "$BLUE" "${BASE_DIR}/docker-compose.yml") file. See what horrors I've created."
echo "   - $(color_echo "$RED" "IF YOU ENABLED THEM:") You MUST configure Recyclarr and Unpackerr manually!"
echo "     - Recyclarr needs: $(color_echo "$BLUE" "${BASE_DIR}/config/recyclarr/recyclarr.yml")"
echo "     - Unpackerr needs env vars (see compose file comments) OR: $(color_echo "$BLUE" "${BASE_DIR}/config/unpackerr/unpackerr.conf")"
echo "   - $(color_echo "$RED" "IF YOU ENABLED IT:") Configure Homepage dashboard widgets/services in:"
echo "     - $(color_echo "$BLUE" "${BASE_DIR}/config/homepage/") (bookmarks.yaml, services.yaml, etc.)"
echo ""
echo "2. $(color_echo "$YELLOW" "Navigate There:")"
echo "   cd \"${BASE_DIR}\""
echo ""
echo "3. $(color_echo "$YELLOW" "Hold Your Breath and Run:")"
echo "   ${DOCKER_COMPOSE_CMD} up -d"
echo "   (The '-d' runs it in the background so you can close the terminal and pretend nothing happened)"
echo ""

# Figure out if we should suggest http or https
protocol="http"
if [[ -n "${DNS_PROVIDER}" && "${DNS_PROVIDER}" != "None" ]]; then
    protocol="https"
fi

echo "4. $(color_echo "$YELLOW" "Access Your New Toys (If They Work):")"
echo "   - Traefik Dashboard: ${protocol}://traefik.${DOMAIN}"
echo "   - Other stuff: ${protocol}://<service_name>.${DOMAIN}"
echo "     (e.g., ${protocol}://jellyfin.${DOMAIN}, ${protocol}://sonarr.${DOMAIN})"
echo "   - If you chose 'Local-Network-Only' and don't have magic local DNS:"
echo "     Use http://<your-server-ip>:<port> (Check compose file or Traefik dashboard for ports exposed via Traefik/Gluetun)"
echo ""
echo ""
add_pause 1
color_echo "$YELLOW" "Pro Tip:" "It might take a few minutes for everything to start up, especially Traefik getting certs (if using HTTPS)."
echo "If things explode, check the logs: '${DOCKER_COMPOSE_CMD} logs -f <service_name>'"
echo "To stop everything: '${DOCKER_COMPOSE_CMD} down'"
echo "To stop and remove volumes (DANGER!): '${DOCKER_COMPOSE_CMD} down -v'"
echo "----------------------------------------"
color_echo "$GREEN" "Good luck. You'll probably need it.${NC}"

exit 0
