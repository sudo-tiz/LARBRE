#!/bin/sh

# Luke's Auto Rice Bootstrapping Script (LARBS) - Improved
# by Luke Smith <luke@lukesmith.xyz>
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

dotfilesrepo="https://github.com/sudo-Tiz/dotfilesV2.git"
progsfiles="https://raw.githubusercontent.com/sudo-Tiz/LARBRE/main/essential-progs.csv
https://raw.githubusercontent.com/sudo-Tiz/LARBRE/main/additional-progs.csv"
aurhelper="yay"
repobranch="master"
export TERM=ansi

rssurls="https://www.archlinux.org/feeds/news/ \"tech\"
https://github.com/sudo-Tiz/dotfilesV2/commits/master.atom \"~Sudo-Tiz dotfiles\""

### FUNCTIONS ###

installpkg() {
  pacman --noconfirm --needed -S "$1"
}

error() {
  printf "%s\n" "$1" >&2
  exit 1
}

welcomemsg() {
  whiptail --title "Welcome!" \
    --msgbox "This script will automatically install a fully-featured Linux desktop, which I use as my main machine." 10 60

  whiptail --title "Important Note!" --yes-button "All ready!" \
    --no-button "Return..." \
    --yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
}

getuserandpass() {
  name=$(whiptail --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
  while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
    name=$(whiptail --nocancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
  done
  pass1=$(whiptail --nocancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
  pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
  while ! [ "$pass1" = "$pass2" ]; do
    unset pass2
    pass1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
    pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
  done
}

usercheck() {
  ! { id -u "$name" >/dev/null 2>&1; } ||
    whiptail --title "WARNING" --yes-button "CONTINUE" \
      --no-button "No wait..." \
      --yesno "The user \`$name\` already exists on this system. LARBS can install for a user already existing, but it will OVERWRITE any conflicting settings/dotfiles on the user account.\\n\\nLARBS will NOT overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that LARBS will change $name's password to the one you just gave." 14 70
}

preinstallmsg() {
  whiptail --title "Let's get this party started!" --yes-button "Let's go!" \
    --no-button "No, nevermind!" \
    --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || {
    clear
    exit 1
  }
}

adduserandpass() {
  whiptail --infobox "Adding user \"$name\"..." 7 50
  useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
    usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
  export repodir="/home/$name/.local/src"
  mkdir -p "$repodir"
  chown -R "$name":wheel "$(dirname "$repodir")"
  echo "$name:$pass1" | chpasswd
  unset pass1 pass2
}

refreshkeys() {
  case "$(readlink -f /sbin/init)" in
  *systemd*)
    whiptail --infobox "Refreshing Arch Keyring..." 7 40
    pacman --noconfirm -S archlinux-keyring
    ;;
  *)
    whiptail --infobox "Enabling Arch Repositories..." 7 40
    pacman --noconfirm --needed -S artix-keyring artix-archlinux-support
    grep -q "^\[extra\]" /etc/pacman.conf ||
      echo "[extra]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
    pacman -Sy --noconfirm
    pacman-key --populate archlinux
    ;;
  esac
}

manualinstall() {
  pacman -Qq "$1" && return 0
  whiptail --infobox "Installing \"$1\" manually." 7 50
  sudo -u "$name" mkdir -p "$repodir/$1"
  sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
    --no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
    {
      cd "$repodir/$1" || return 1
      sudo -u "$name" git pull --force origin master
    }
  cd "$repodir/$1" || exit 1
  sudo -u "$name" -D "$repodir/$1" makepkg --noconfirm -si || return 1
}

maininstall() {
  whiptail --title "LARBS Installation" --infobox "Installing \`$1\` ($n of $total). $2" 9 70
  installpkg "$1" || printf "ERROR: Failed to install %s\n" "$1"
}

gitmakeinstall() {
  progname="${1##*/}"
  progname="${progname%.git}"
  dir="$repodir/$progname"
  whiptail --title "LARBS Installation" \
    --infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $2" 8 70
  sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
    --no-tags -q "$1" "$dir" ||
    {
      cd "$dir" || return 1
      sudo -u "$name" git pull --force origin master
    }
  cd "$dir" || exit 1
  if [ -f justfile ] || [ -f Justfile ]; then
    just && just install
  else
    make && make install
  fi
  cd /tmp || return 1
}

aurinstall() {
  whiptail --title "LARBS Installation" \
    --infobox "Installing \`$1\` ($n of $total) from the AUR. $2" 9 70
  echo "$aurinstalled" | grep -q "^$1$" && return 0
  sudo -u "$name" $aurhelper -S --noconfirm "$1" || printf "ERROR: Failed to install AUR package %s\n" "$1"
}

installationloop() {
  : >/tmp/progs.csv
  for f in $progsfiles; do
    ([ -f "$f" ] && cat "$f" || curl -Ls "$f") | sed '/^#/d;/^[[:space:]]*$/d' >>/tmp/progs.csv
  done
  total=$(wc -l </tmp/progs.csv)
  aurinstalled=$(pacman -Qqm)
  n=0
  while IFS=, read -r tag program comment; do
    n=$((n + 1))
    echo "$comment" | grep -q "^\".*\"$" &&
      comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
    case "$tag" in
    "A") aurinstall "$program" "$comment" ;;
    "G") gitmakeinstall "$program" "$comment" ;;
    *) maininstall "$program" "$comment" ;;
    esac
  done </tmp/progs.csv
}

putgitrepo() {
  whiptail --infobox "Downloading and installing config files..." 7 60
  [ -z "$3" ] && branch="master" || branch="$repobranch"
  dir=$(mktemp -d)
  [ ! -d "$2" ] && mkdir -p "$2"
  chown "$name":wheel "$dir" "$2"
  sudo -u "$name" git clone --depth 1 --single-branch --no-tags -q \
    --recursive -b "$branch" --recurse-submodules "$1" "$dir" || error "Failed to clone dotfiles"
  sudo -u "$name" cp -rfT "$dir" "$2"
  rm -rf "$dir"
}

setupbatterycheck() {
  # Find battery - exit gracefully if no battery (desktop)
  BATTERY_PATH=$(find /sys/class/power_supply -name "BAT*" -type d | head -1)
  [ -z "$BATTERY_PATH" ] && return 0

  whiptail --infobox "Setting up battery monitoring..." 7 50

  # Create battery check script
  cat <<EOF >/usr/local/bin/check_battery
#!/bin/bash
BATTERY_PATH="$BATTERY_PATH"
battery_percentage=\$(cat "\$BATTERY_PATH/capacity")

# Skip if charging
if grep -q "Charging" "\$BATTERY_PATH/status" 2>/dev/null; then
    exit 0
fi

if [ "\$battery_percentage" -lt 3 ]; then
    # Notify all users before hibernating
    for session in \$(loginctl list-sessions --no-legend | awk '{print \$1}'); do
        user=\$(loginctl show-session "\$session" -p Name --value 2>/dev/null)
        [ -n "\$user" ] && sudo -u "\$user" DISPLAY=:0 notify-send -u critical "Critical Battery" "Hibernating now! (\${battery_percentage}%)" 2>/dev/null || true
    done
    sleep 2
    systemctl hibernate
elif [ "\$battery_percentage" -lt 10 ]; then
    # Notify all users
    for session in \$(loginctl list-sessions --no-legend | awk '{print \$1}'); do
        user=\$(loginctl show-session "\$session" -p Name --value 2>/dev/null)
        [ -n "\$user" ] && sudo -u "\$user" DISPLAY=:0 notify-send "Low Battery" "Battery: \${battery_percentage}%" 2>/dev/null || true
    done
fi
EOF
  chmod +x /usr/local/bin/check_battery

  # Create systemd service
  cat <<'EOF' >/etc/systemd/system/battery-monitor.service
[Unit]
Description=Battery Monitor

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check_battery
EOF

  cat <<'EOF' >/etc/systemd/system/battery-monitor.timer
[Unit]
Description=Battery Monitor Timer

[Timer]
OnBootSec=30
OnUnitActiveSec=30

[Install]
WantedBy=timers.target
EOF

  # Enable with symbolic links
  systemctl daemon-reload
  ln -sf /etc/systemd/system/battery-monitor.timer /etc/systemd/system/timers.target.wants/
  systemctl start battery-monitor.timer
}

finalize() {
  whiptail --title "All done!" \
    --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n-Luke" 13 80
}

### THE ACTUAL SCRIPT ###

# Check if user is root on Arch distro. Install whiptail.
pacman --noconfirm --needed -Sy libnewt ||
  error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Welcome user
welcomemsg || error "User exited."

# Get and verify username and password
getuserandpass || error "User exited."

# Give warning if user already exists
usercheck || error "User exited."

# Last chance for user to back out before install
preinstallmsg || error "User exited."

### The rest of the script requires no user input ###

# Refresh Arch keyrings
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

# Install essential packages
for x in curl ca-certificates base-devel git just ntp zsh; do
  whiptail --title "LARBS Installation" \
    --infobox "Installing \`$x\` which is required to install and configure other programs." 8 70
  installpkg "$x"
done

# Synchronize system time
whiptail --title "LARBS Installation" \
  --infobox "Synchronizing system time to ensure successful and secure installation of software..." 8 70
ntpd -q -g >/dev/null 2>&1

# Add user and set password
adduserandpass || error "Error adding username and/or password."

# Handle sudoers backup
[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers

# Allow user to run sudo without password for AUR installation
trap 'rm -f /etc/sudoers.d/larbs-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL
Defaults:%wheel,root runcwd=*" >/etc/sudoers.d/larbs-temp

# Make pacman colorful and faster
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf

# Use all cores for compilation
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

# Install AUR helper
manualinstall $aurhelper || error "Failed to install AUR helper."

# Make sure git AUR packages get updated
$aurhelper -Y --save --devel

# Install all packages from CSV files
# To add extra packages, append a URL or local path to $progsfiles before running:
#   progsfiles="$progsfiles\nhttps://example.com/foo.csv"
installationloop

# Install dotfiles
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch" ||
  error "Error downloading and installing dotfiles."

# Setup newsboat if URLs file doesn't exist
[ ! -f "/home/$name/.config/newsboat/urls" ] &&
  echo "$rssurls" >"/home/$name/.config/newsboat/urls"

# Disable system beep
rmmod pcspkr 2>/dev/null || true
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Set zsh as default shell and create directories
chsh -s /bin/zsh "$name"
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
sudo -u "$name" mkdir -p "/home/$name/.config/abook/"
sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"

# Setup PAM autologin and gnome keyring
cp /etc/pam.d/login /etc/pam.d/login.bak
cat <<EOL >/etc/pam.d/login
#%PAM-1.0

auth       required     pam_autologin.so
auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      system-local-login
auth       optional     pam_gnome_keyring.so
account    include      system-local-login
session    include      system-local-login
session    optional     pam_gnome_keyring.so auto_start
EOL
touch /etc/security/autologin.conf

# Autologin to user
mkdir /etc/systemd/system/getty@tty1.service.d/
cat /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --skip-login - $TERM
EOF

# Configure sudo permissions
echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-larbs-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm" >/etc/sudoers.d/01-larbs-cmds-without-password
echo "Defaults editor=/usr/bin/nvim" >/etc/sudoers.d/02-larbs-visudo-editor

# Allow dmesg for users
mkdir -p /etc/sysctl.d
echo "kernel.dmesg_restrict = 0" >/etc/sysctl.d/dmesg.conf

# Setup battery monitoring if laptop
setupbatterycheck

# Setup dnsmasq with Quad9 and Mullvad server with DNS over TLS
cat <<'EOF' >/etc/NetworkManager/dnsmasq.d/custom.conf
# === DNS LOCAL ===
listen-address=127.0.0.1

# === CACHE ===
cache-size=1000

# === DNSSEC (optionnel) ===
# dnssec

# === PARALLELISATION ===
dns-forward-max=500

# === DOT (DNS over TLS) ===
# QUAD9
server=9.9.9.9#853 # Malware
server=149.112.112.112#853 # Malware
# MULLVAD
server=194.242.2.5#853 # Ads + Trackers + Malware + Social media
server=194.242.2.4#853 # Ads + Trackers + Malware

# === LOCAL ENTRIES ===
address=/mabbox.bytel.fr/192.168.1.254
address=/bonas/192.168.1.192
EOF

# Setup NetworkManager.conf
cat <<'EOF' >/etc/NetworkManager/NetworkManager.conf
[main]
dns=dnsmasq
rc-manager=symlink

[device]
wifi.scan-rand-mac-address=yes
wifi.backend=iwd

[connection]
ethernet.cloned-mac-address=random
wifi.cloned-mac-address=random
EOF

# GTK dark theme
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Remove powerbutton action
sed -i 's/^#HandlePowerKey=.*/HandlePowerKey=ignore/' /etc/systemd/login.conf

# Cleanup temporary sudo permissions
rm -f /etc/sudoers.d/larbs-temp

# Final message
finalize
