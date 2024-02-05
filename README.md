## About gentoo-install

This project aspires to be your favourite way to install gentoo.
It aims to provide a smooth installation experience, both for beginners and experts.
You may configure it by using a menuconfig-inspired interface or simply via a config file.

It supports the most common disk layouts, different file systems like ext4, ZFS and btrfs as well
as additional layers such as LUKS or mdraid. It also supports both EFI (recommended) and BIOS boot,
and can be used with systemd or OpenRC as the init system. SSH can also be configured to allow using an automation framework
like [Ansible](https://github.com/ansible/ansible) or [Fora](https://github.com/oddlama/fora) to automate beyond system installation.

[Usage](#usage) |
[Overview](#overview) |
[Updating the Kernel](#updating-the-kernel) |
[Recommendations](#recommendations) |
[FAQ](#troubleshooting-and-faq)

![](contrib/screenshot_configure.png)

This installer might appeal to you if

- you want to try gentoo without initially investing a lot of time, or fully committing to it yet.
- you already are a gentoo expert but want an automatic and repeatable best-practices installation.

Of course, we do encourage everyone to install gentoo manually. You will learn a lot if you
haven't done so already.

## Usage

First, boot into a live environment of your choice. I recommend using an [Arch Linux](https://www.archlinux.org/download/) live ISO,
as the installer will then be able to automatically download required programs or setup ZFS support on the fly.
Afterwards, proceed with the following steps:

```bash
pacman -Sy git  # (Archlinux) Install git in live environment, then clone:
git clone "https://github.com/oddlama/gentoo-install"
cd gentoo-install
./configure     # configure to your liking, save as gentoo.conf
./install       # begin installation
```

Every option is explained in detail in `gentoo.conf.example` and in the help menus of the TUI configurator.
When installing, you will be asked to review the partitioning before anything critical is done.

The installer should be able to run without any user supervision after partitioning, but depending
on the current state of the gentoo repository, you might need to intervene in case a package fails
to emerge. The critical commands will ask you what to do in case of a failure. If you encounter a
problem you cannot solve, you might want to consider getting in contact with some experienced people
on [IRC](https://www.gentoo.org/get-involved/irc-channels/) or [Discord](https://discord.com/invite/gentoolinux).

If you need to enter an installed system in a chroot to fix something (e.g. after rebooting your live system),
you can always clone the installer, mount your main drive under `/mnt` and use `./install --chroot /mnt` to
just chroot into your system.

## Overview

The installer performs the following main steps (in roughly this order),
with some parts depending on the chosen configuration:

1. Partition disks (highly dependent on configuration)
2. Download and extract stage3 tarball (with cryptographic verification)
   \[Continues in chroot from here\]
3. Setup portage (initial rsync/git sync, run mirrorselect, create zz-autounmask files)
4. Base system configuration (hostname, timezone, keymap, locales)
5. Install required packages (git, kernel, ...)
6. Make system bootable (generate fstab, build initramfs, create efibootmgr/syslinux boot entry)
7. Ensure minimal working system (automatic wired networking, install eix, set root password)
   - (Optional) Install sshd with secure config (no password logins)
   - (Optional) Install additional packages provided in config

The goal of the installer is just to setup a minimal gentoo system following best-practices.
Anything beyond that is considered out-of-scope (with the exception of configuring sshd).
Here are some things that you might want to consider doing after the system installation is finished:

1. Read the news with `eselect news read`.
2. Compile a custom kernel and remove `gentoo-kernel-bin`
3. Adjust `/etc/portage/make.conf`
   - Set `CFLAGS` to `<march_native_flags> -O2 -pipe` for native builds by using the `resolve-march-native` tool
   - Set `CPU_FLAGS_X86` using the `cpuid2cpuflags` tool
4. Use a safe umask like `umask 077`

### (Optional) sshd

The script can provide a fully configured ssh daemon with reasonably good security settings.
It will by default only allow ed25519 keys, restrict key exchange
algorithms to a reasonable subset, disable any password based authentication,
and only allow root to login.

You can provide keys that will be written to root's `.ssh/authorized_keys` file. This will allow
you to directly continue your setup with your favourite infrastructure management software.

### (Optional) Additional packages

You can add any amount of additional packages to be installed on the target system.
These will simply be passed to a final `emerge` call before the script is done,
where autounmasking will also be done automatically. It is recommended to keep
this to a minimum, because of the quite "interactive" nature of gentoo package management ;)

## Updating the kernel

By default, the installed system uses gentoo's binary kernel distribution (`sys-kernel/gentoo-kernel-bin`)
together with an initramfs generated by dracut. This ensures that the installed system works on all common hardware configurations.
Feel free to replace this with a custom-built kernel (and possibly remove/adjust the initramfs) when the system is booted.

The installer will provide the convenience script `generate_initramfs.sh` in `/boot/efi/`
or `/boot/bios` which may be used to generate a new initramfs for the given kernel version.
Depending on whether your system uses EFI or BIOS boot, you will also find your kernel and initramfs in different locations:

```bash
# EFI
kernel="/boot/efi/vmlinuz.efi"
initrd="/boot/efi/initramfs.img"
# BIOS
kernel="/boot/bios/vmlinuz-current"
initrd="/boot/bios/initramfs.img"
```

In both cases, the update procedure is as follows:

1. Emerge new kernel
2. `eselect kernel set <kver>`
3. Backup old kernel and initramfs (`mv "$kernel"{,.bak}`, `mv "$initrd"{,.bak}`)
4. Generate new initramfs for this kernel `generate_initramfs.sh <kver> "$initrd"`
5. Copy new kernel `cp /boot/kernel-<kver> "$kernel"` (for systemd) or `cp /boot/vmlinuz-<kver> "$kernel"` (for openrc)

## Recommendations

This project started out as a way of documenting a best-practices installation for myself.
As the project grew larger, I've added more configuration options to suit legacy needs.
Below I've outlined several decisions I've made for this project, or decisions you
have during configuration. If you intend on setting up a modern system, you might want
to check them out. Please keep in mind that those are all based on my personal opinions and
experience. Your mileage may vary.

#### EFI vs BIOS

Use EFI. BIOS is old and deprecated for a long time now.
Only certain VPS hosters may require you to use BIOS still (time to write to them about that!)

#### EFIstub booting

Don't install a bootloader when this script is done, except you absolutely need one.
The kernel can directly be booted by EFI without need for a bootloader.
By default, this script will use efibootmgr to add a bootentry directly to your "mainboard's bootselect" (typically F12).
Nowadays, there's just no reason to use GRUB, syslinux, or similar bootloaders by default.
They only add additional time to your boot, and even dualbooting Windows works just fine without one.
Only if you require frequent editing of kernel parameters, or want kernel autodiscovery from attached media
you might want to consider using one of these. For the average (advanced) user this isn't necessary.

If you want to add more boot options or want to learn about efibootmgr, refer to [this page on the gentoo wiki](https://wiki.gentoo.org/wiki/Efibootmgr).

#### Modern file systems

I recommend using a modern file system like ZFS, both on desktops and servers.
It provides transparent block-level compression, instant snapshots and full-disk encryption.
Generally, encrypting your root fs doesn't cost you anything and protects your data in case you lose your device.

#### Systemd vs OpenRC

I will not entertain the religious eternal debate here. Both are fine init systems, and
I've been using both *a lot*. If you cannot decide, here are some objective facts:

- OpenRC is a service manager. Setting up all the other services is a lot of work, but you will learn a lot.
- Systemd is an OS-level software suite. It brings an insane amount of features with a steep learning curve.

Here's a non-exhaustive list of things you will ~do manually~ learn when using OpenRC,
that are already provided for in systemd: udev, dhcp, acpi events (power/sleep button),
cron jobs, reliable syslog, logrotate, process sandboxing, persistent backlight setting, persistent audio mute-status, user-owned login sessions, ...

Make of this what you will, both have their own quirks. Choose your poison.

#### Miscellaneous

- Use the newer iwd for WiFi instead of wpa_supplicant
- (If systemd) Use timers instead of cron jobs

## Troubleshooting and FAQ

After the initial sanity check, the script should be able to finish unattendedly.
But given the unpredictability of future gentoo versions, you might still run into issues
once in a while.

The script checks every command for success, so if anything fails during installation,
you will be given a proper message of what went wrong. Inside the chroot,
most commands will be executed in a checked loop, and allow you to interactively
fix problems with a shell, to retry, or to skip the command. You can report
issues specific to this script on the issue tracker. To seek help
regarding gentoo in general, visit the official [IRC](https://www.gentoo.org/get-involved/irc-channels/)
or [Discord](https://discord.com/invite/gentoolinux).

If you experience any issues after rebooting and need to fix something inside the chroot,
you can use the installer to chroot into an existing system. Run `./install --help` for more infos.

#### Q: ZFS cannot be installed in the chroot due to an unsupported kernel version

**A:** The newest stable ZFS module may require a kernel version that is newer than what is provided on gentoo stable.
If you encounter this problem, you might be able to fix the problem by switching to testing by dropping to a shell temporarily:

```
# Press S<Enter> when asked about what to do next.
# This opens an emergency shell in the chroot.
echo 'ACCEPT_KEYWORDS="~amd64"' >> /etc/portage/make.conf # Enable testing for your architecture.
emerge -v gentoo-kernel-bin                               # Update kernel to newest version
exit # Ctrl-D
# Now select 'retry' when asked about what to do next.
```

#### Q: I get errors after partitioning about blkid not being able to find a UUID

**A:** Be sure that all devices are unmounted and not in use before starting the script.
Use `wipefs -a <DEVICE>` on your partitions or fully wipe the disk before use.
The new partitions probably align with previously existing partitions that had
filesystems on them. Some filesystems signatures like those of ZFS can coexist with
other signatures and may cause blkid to find ambiguous information.

## References

* [Gentoo AMD64 Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
* [Sakaki's EFI Install Guide](https://wiki.gentoo.org/wiki/Sakaki%27s_EFI_Install_Guide)
