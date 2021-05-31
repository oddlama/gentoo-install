## About gentoo-install

A installer for gentoo with a simple menuconfig inspired configuration TUI.
The configurator is only used to generate a `gentoo.conf` file, which can also be
edited by hand if desired. An example configuration is provided with the repository.

## Quick start

First, boot into a live environment of your choice. I recommend using an [Arch Linux](https://www.archlinux.org/download/) live iso,
as the installer will then be able to automatically download required programs or setup zfs support on the fly. After that,
proceed with the following steps:

1. Either clone this repo or download and extract a copy
1. Run `./configure` and save your desired configuration
1. Begin installation using `./install`

Every option is explained in detail in `gentoo.conf.example` and in the help menu popups in the configurator.
When installing, you will be asked to review the partitioning before anything critical is done.

## Overview

This script performs a reasonably minimal installation of gentoo. An EFI system is highly
recommended, but legacy BIOS boot is also supported. The script supports both systemd (default)
and OpenRC as the init system.

The system will use `sys-kernel/gentoo-kernel-bin`, which should be suitable
to boot most systems out of the box. It is strongly recommend to replace this kernel
with a custom built one, when the system is functional.

1. Partition disks (supports gpt, raid, luks)
1. Download and cryptographically verify the newest stage3 tarball
1. Extract the stage3 tarball
1. Sync portage tree
1. Configure portage (create zz-autounmask files, configure `make.conf`)
1. Select the fastest gentoo mirrors if desired
1. Configure the base system (timezone, keymap, locales, ...)
1. Install git and other required tools (e.g. zfs if you have used zfs)
1. Install `sys-kernel/gentoo-kernel-bin` (until you can compile your own)
1. Generate an initramfs with dracut
1. Create efibootmgr entry or install syslinux depending on whether your system uses EFI or BIOS
1. Generate fstab
1. (Optional components from below)
1. Asks if a root password should be set

Also, optionally the following will be done:

* Install sshd with secure config
* Install dhcpcd (only for OpenRC)
* Install additional packages provided in config

Anything else is probably out of scope for this script, but you can obviously do
anything later on when the system is booted. Here are some things that you probably
want to consider doing after the base system installation is finished:

* Read the news with `eselect news read`.
* Compile a custom kernel and remove `gentoo-kernel-bin`
* Adjust `/etc/portage/make.conf`
  - Set `CFLAGS` to `-O2 -pipe -march=native` for native builds
  - Set `CPU_FLAGS_X86` using the `cpuid2cpuflags` tool
  - Set `FEATURES="buildpkg"` if you want to build binary packages
* Use a safe umask like `umask 0077`

If you are looking for a way to detect and manage your kernel configuration, have a look at [autokernel](https://github.com/oddlama/autokernel).

## Usage

Installing gentoo with this script is simple.

1. Boot into the live system of your choice. As the script requires some utilities,
   I recommend using a live system where you can quickly install new software.
   Any [Arch Linux](https://www.archlinux.org/download/) live iso works fine.
2. Clone this repository
3. Run `./configure` or create your own `gentoo.conf` following the example file.
   Particularily pay attention to the device which will be partitioned.
   The script will ask for confirmation before doing any partitioning - but better be safe here.
4. Execute `./install`.

The script should be able to run without any user supervision after partitioning, but depending
on the current state of the gentoo repository you might need to intervene in case a package fails
to emerge. The critical commands will ask you what to do in case of a failure.

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

### Troubleshooting

In theory, after the initial sanity check, the script should be able to finish unattendedly.
But given the unpredictability of future gentoo versions, you might still run into an issue.

The script checks every command for success, so if anything fails during installation,
you will be given a proper message of what went wrong. Inside the chroot,
most commands will be executed in a checked loop, and allow you to interactively
fix problems with a shell, to retry, or to skip the command.

## References

* [Sakaki's EFI Install Guide](https://wiki.gentoo.org/wiki/Sakaki%27s_EFI_Install_Guide)
* [Gentoo AMD64 Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64)
