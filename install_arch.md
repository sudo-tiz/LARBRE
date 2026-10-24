# Install Arch Linux

Setup: UEFI, GPT, GRUB, LUKS encryption, ext4, swapfile, optional LVM.

Examples use French settings (`fr` keyboard, `Europe/Paris`). Change them as needed.
Replace every `<placeholder>` with your own value.

## 1. Prepare the live system

1.  Download the ISO from <https://archlinux.org/download/> and write it to a USB drive.
    **This erases the USB drive.** Check the device name with `lsblk` first.

    ```sh
    dd if=archlinux.iso of=/dev/<usb> bs=4M status=progress oflag=sync
    ```

1.  Boot from the USB drive, then set the keyboard layout:

    ```sh
    loadkeys fr
    ```

1.  Check that you booted in UEFI mode. The directory must be listed without error:

    ```sh
    ls /sys/firmware/efi/efivars
    ```

1.  Connect to the internet. Wired is easiest (works automatically).
    For Wi-Fi, use `iwctl` ([wiki](https://wiki.archlinux.org/title/Iwd#iwctl)). Then check:

    ```sh
    ping -c 3 archlinux.org
    ```

## 2. Partition, encrypt, format

1.  Find your disk name (`/dev/sda`, `/dev/nvme0n1`, ...):

    ```sh
    lsblk
    ```

1.  Create the partitions.
    **WARNING: this erases the entire disk.** Don't use it to keep Windows;
    in that case create the partitions manually with `fdisk`.

    | Partition | Size      | Use                               |
    | --------- | --------- | --------------------------------- |
    | 1         | 512M      | EFI system partition (`/efi`)     |
    | 2         | 1G        | Boot (`/boot`, kernels)           |
    | 3         | remaining | LUKS (encrypted system)           |

    ```sh
    sfdisk /dev/<disk> << 'EOF'
    label: gpt
    ,512M,U
    ,1G,L
    ,,L
    EOF
    ```

    Partitions are named `<disk>1`, `<disk>2`, `<disk>3` (`<disk>p1`... for NVMe).
    Check with `lsblk`. Below they are called `<efi>`, `<boot>` and `<luks>`.

1.  Format the EFI and boot partitions:

    ```sh
    mkfs.fat -F 32 /dev/<efi>
    mkfs.ext4 /dev/<boot>
    ```

1.  Encrypt the third partition and open it.
    `cryptroot` is just a name, you can change it.

    ```sh
    cryptsetup luksFormat /dev/<luks>
    cryptsetup open /dev/<luks> cryptroot
    ```

1.  Create the filesystems. Choose **one** option.

    **Option A: no LVM (simplest, recommended).** One root partition:

    ```sh
    mkfs.ext4 /dev/mapper/cryptroot
    mount /dev/mapper/cryptroot /mnt
    ```

    **Option B: LVM.** Useful for a separate `/home` or resizable volumes.
    Leaves 256MiB free in the volume group (needed by `e2scrub`):

    ```sh
    pvcreate /dev/mapper/cryptroot
    vgcreate vg0 /dev/mapper/cryptroot
    lvcreate -L 100G vg0 -n root
    lvcreate -l 100%FREE vg0 -n home
    lvreduce -y -L -256M vg0/home
    mkfs.ext4 /dev/vg0/root
    mkfs.ext4 /dev/vg0/home
    mount /dev/vg0/root /mnt
    mount --mkdir /dev/vg0/home /mnt/home
    ```

1.  Mount the boot partitions:

    ```sh
    mount --mkdir /dev/<boot> /mnt/boot
    mount --mkdir /dev/<efi> /mnt/efi
    ```

1.  Create a swapfile. Use at least your RAM size if you want hibernation.

    ```sh
    mkswap -U clear --size 8G --file /mnt/swapfile
    swapon /mnt/swapfile
    ```

## 3. Install the system

1.  Install the base system. Choose `intel-ucode` or `amd-ucode` for your CPU.
    Add `lvm2` if you chose Option B.

    ```sh
    pacstrap -K /mnt base base-devel linux linux-firmware intel-ucode e2fsprogs \
      grub efibootmgr networkmanager sof-firmware git neovim man-db man-pages texinfo sudo zsh
    ```

    If you get signature/key errors, fix the keyring and retry:

    ```sh
    pacman-key --init && pacman-key --populate archlinux && archlinux-keyring-wkd-sync
    ```

1.  Generate `/etc/fstab` (how partitions are mounted at boot, swapfile included):

    ```sh
    genfstab -U /mnt >> /mnt/etc/fstab
    ```

1.  Enter the new system:

    ```sh
    arch-chroot /mnt
    ```

## 4. Configure the system (inside the chroot)

1.  Timezone and clock (list zones with `ls /usr/share/zoneinfo/`):

    ```sh
    ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
    hwclock --systohc
    ```

1.  Language and keyboard:

    ```sh
    sed -i 's/^#\(en_US.UTF-8\)/\1/' /etc/locale.gen
    locale-gen
    echo LANG=en_US.UTF-8 > /etc/locale.conf
    echo KEYMAP=fr > /etc/vconsole.conf
    ```

1.  Hostname:

    ```sh
    echo <hostname> > /etc/hostname
    ```

1.  Passwords and user. Members of `wheel` can use `sudo`.

    ```sh
    passwd
    useradd -m -G wheel,video,audio,input -s /bin/zsh <username>
    passwd <username>
    echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
    ```

1.  Configure the initramfs (early boot image) to unlock the disk.
    If you chose Option B, add `lvm2` after `sd-encrypt`.

    ```sh
    echo 'HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)' \
      > /etc/mkinitcpio.conf.d/hooks.conf
    mkinitcpio -P
    ```

1.  Install GRUB:

    ```sh
    grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
    ```

1.  Tell GRUB where the encrypted disk and the hibernation swapfile are.
    The kernel root must be `/dev/mapper/cryptroot` (Option A) or `/dev/vg0/root` (Option B).

    ```sh
    ROOT=/dev/mapper/cryptroot   # Option B: ROOT=/dev/vg0/root
    LUKS_UUID=$(blkid -s UUID -o value /dev/<luks>)
    ROOT_UUID=$(findmnt -no UUID /)
    OFFSET=$(filefrag -v /swapfile | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')

    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"rd.luks.name=$LUKS_UUID=cryptroot root=$ROOT resume=UUID=$ROOT_UUID resume_offset=$OFFSET\"|" /etc/default/grub
    sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"|' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    ```

    Check the result: `grep ^GRUB_CMDLINE /etc/default/grub`.

1.  Enable the network at boot:

    ```sh
    systemctl enable NetworkManager
    ```

1.  Leave the chroot, unmount and reboot (remove the USB drive):

    ```sh
    exit
    umount -R /mnt
    reboot
    ```

Arch is now installed 🎉

# Notes

## Backup the LUKS header

If the LUKS header gets damaged, your data is lost forever.
Back it up and store the file somewhere safe (another USB drive, not this disk).

```sh
sudo cryptsetup luksHeaderBackup /dev/<luks> --header-backup-file luks-header-backup-$(date -I)
```

Restore it if needed:

```sh
sudo cryptsetup luksHeaderRestore /dev/<luks> --header-backup-file /path/to/backup_header_file
```

## Install drivers

**Intel**:

```sh
sudo pacman -S mesa intel-media-driver libva-intel-driver vulkan-intel
```

**NVIDIA**:

```sh
sudo pacman -S nvidia
```

**VirtualBox**:

```sh
sudo pacman -S virtualbox-guest-utils
```

## Run LARBRE to install the desktop environment

You can install a desktop environment manually, or run `larbre.sh` to install mine
(see [dotfiles](https://github.com/sudo-Tiz/dotfilesV2)):

```sh
curl -LO https://raw.githubusercontent.com/sudo-Tiz/LARBRE/main/larbre.sh
sudo sh larbre.sh
```
