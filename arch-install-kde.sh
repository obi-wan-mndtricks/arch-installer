#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "Run this as root from an Arch live environment (archiso)."
  exit 1
fi

echo "Arch KDE installer — interactive. This will partition and install to a disk."

read -rp "Target disk (e.g. /dev/sda): " DISK
if [[ ! -b "$DISK" ]]; then
  echo "Block device not found: $DISK"
  exit 1
fi

read -rp "Install for UEFI system? [Y/n]: " uefi_ans
uefi_ans=${uefi_ans:-Y}
if [[ $uefi_ans =~ ^[Nn] ]]; then
  UEFI=0
else
  UEFI=1
fi

read -rp "Hostname (laptop): " HOSTNAME
HOSTNAME=${HOSTNAME:-arch-laptop}
read -rp "New username: " USERNAME
read -rsp "Password for $USERNAME: " USERPASS
echo
read -rsp "Root password: " ROOTPASS
echo

echo "About to wipe $DISK and install Arch with KDE. Press Ctrl-C to abort, or Enter to continue."
read -r

if [[ $UEFI -eq 1 ]]; then
  parted -s "$DISK" mklabel gpt
  parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
  parted -s "$DISK" set 1 boot on
  parted -s "$DISK" mkpart primary ext4 513MiB 100%
  EFI_PART=${DISK}1
  ROOT_PART=${DISK}2
else
  parted -s "$DISK" mklabel msdos
  parted -s "$DISK" mkpart primary ext4 1MiB 100%
  ROOT_PART=${DISK}1
fi

if [[ $UEFI -eq 1 ]]; then
  mkfs.fat -F32 "$EFI_PART"
fi
mkfs.ext4 -F "$ROOT_PART"

mount "$ROOT_PART" /mnt
if [[ $UEFI -eq 1 ]]; then
  mkdir -p /mnt/boot/efi
  mount "$EFI_PART" /mnt/boot/efi
fi

echo "Installing base system packages (may take a while)..."
pacstrap /mnt base linux linux-firmware sudo nano zsh bash-completion networkmanager wpa_supplicant dialog os-prober mtools dosfstools base-devel --noconfirm --needed

echo "Installing minimal KDE Plasma (Wayland), audio, power, and boot packages..."
# Install a minimal KDE Wayland stack (avoid the heavy kde-applications meta-package)
pacstrap /mnt plasma-desktop sddm plasma-wayland-session kwin-wayland plasma-pa libinput --noconfirm --needed || true
pacstrap /mnt mesa pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils pavucontrol --noconfirm --needed
pacstrap /mnt grub efibootmgr intel-ucode amd-ucode --noconfirm --needed || true
pacstrap /mnt network-manager-applet networkmanager --noconfirm --needed
pacstrap /mnt tlp powertop acpi acpid --noconfirm --needed

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash -e <<EOF
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen || true
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1	localhost
::1		localhost
127.0.1.1	$HOSTNAME.localdomain	$HOSTNAME
HOSTS

echo root:$ROOTPASS | chpasswd
useradd -m -G wheel -s /bin/zsh $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd

sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers || true

systemctl enable NetworkManager
systemctl enable sddm
systemctl enable tlp
systemctl enable fstrim.timer

if [ -d /sys/firmware/efi ]; then
  mkdir -p /boot/efi
  mount | grep -q '/boot/efi' || true
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || true
else
  grub-install --target=i386-pc $DISK || true
fi
grub-mkconfig -o /boot/grub/grub.cfg || true

chsh -s /bin/zsh $USERNAME || true
EOF

echo "Installation finished. Unmounting and rebooting in 10 seconds..."
sleep 10
umount -R /mnt || true
reboot
