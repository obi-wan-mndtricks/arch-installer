#!/usr/bin/env bash
set -euo pipefail

# Minimal automated Arch Linux installer tailored for a Dell Latitude 5440
# - Run this from an Arch Linux live USB (UEFI) as root
# - WARNING: this will erase the target disk when you confirm partitioning
# - It creates: EFI (512M FAT32), swap (2G), root (rest: ext4)
# - Installs a lightweight KDE Plasma stack, NetworkManager, SDDM, and common laptop packages

echo "Arch KDE installer for Dell Latitude 5440 — run from Arch live USB"

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root from an Arch Linux live environment." >&2
  exit 1
fi

read -rp $'Target disk (example: /dev/nvme0n1 or /dev/sda)\nEnter target disk: ' TARGET_DISK
if [[ -z "$TARGET_DISK" ]]; then
  echo "No disk provided. Aborting." >&2
  exit 1
fi

read -rp $'This will DESTROY all data on the disk. Type YES to continue: ' CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborted by user."; exit 1
fi

# Determine partition suffix (nvme devices use p1, others use 1)
part_suffix() {
  case "$1" in
    *nvme*) echo "p" ;;
    *) echo "" ;;
  esac
}

PSUFFIX=$(part_suffix "$TARGET_DISK")
EFI_PART="${TARGET_DISK}${PSUFFIX}1"
SWAP_PART="${TARGET_DISK}${PSUFFIX}2"
ROOT_PART="${TARGET_DISK}${PSUFFIX}3"

echo "Partitioning $TARGET_DISK..."
parted --script "$TARGET_DISK" mklabel gpt \
  mkpart primary 1MiB 513MiB \
  set 1 esp on \
  mkpart primary 513MiB 2561MiB \
  mkpart primary 2561MiB 100%

echo "Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"
mkswap "$SWAP_PART"
swapon "$SWAP_PART"
mkfs.ext4 -F "$ROOT_PART"

echo "Mounting partitions..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/efi
mount "$EFI_PART" /mnt/efi

echo "Installing base system (this may take a while)..."
pacstrap /mnt base base-devel linux linux-firmware vim networkmanager sudo

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

cat > /mnt/root/setup-post-install.sh <<'CHROOT'
#!/usr/bin/env bash
set -euo pipefail

echo "Post-install configuration script running inside chroot"

read -rp $'Enter hostname for the new system (example: latitude5440): ' NEW_HOSTNAME
if [[ -z "$NEW_HOSTNAME" ]]; then
  NEW_HOSTNAME=arch-latitude
fi
read -rp $'Enter username to create (will be added to wheel group): ' NEW_USER
if [[ -z "$NEW_USER" ]]; then
  NEW_USER=archuser
fi

echo "Setting timezone to UTC..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo "Locales..."
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$NEW_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1	localhost
::1		localhost
127.0.1.1	$NEW_HOSTNAME.localdomain	$NEW_HOSTNAME
HOSTS

echo "Installing packages: KDE Plasma, SDDM, NetworkManager and laptop tools..."
pacman --noconfirm -Syu
pacman --noconfirm -S plasma sddm sddm-kcm plasma-wayland-session kde-applications konsole dolphin \
  networkmanager network-manager-applet sudo grub efibootmgr intel-ucode mesa pipewire \
  pipewire-pulse wireplumber bluez bluez-utils tlp acpi acpi_call linux-headers linux-firmware

echo "Create user and set passwords (you will be prompted)..."
useradd -m -G wheel -s /bin/bash "$NEW_USER"
echo "Set root password now:"; passwd root
echo "Set password for $NEW_USER now:"; passwd "$NEW_USER"

echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

echo "Enable services: NetworkManager, sddm, bluetooth, tlp..."
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable bluetooth
systemctl enable tlp

echo "Install and configure GRUB for UEFI..."
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "Final sync"
sync
CHROOT

chmod +x /mnt/root/setup-post-install.sh

echo "Entering chroot to finish installation..."
arch-chroot /mnt /root/setup-post-install.sh

echo "Installation complete. You can reboot now."
