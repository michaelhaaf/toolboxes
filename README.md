# michaelhaaf/distroboxes

Fork of [ublue-os/toolboxes][upstream]. The upstream repository provides the template for:

- General purpose ubuntu/fedora/wolfi distroboxes with packages designed for "daily driver" usage
- Instant distrobox launch at login using quadlets and systemd service units

This fork features the following customizations that I find useful that, if generally useful, I may contribute upstream:

- two custom distrobox image definition based on the upstream `wolfi` image
- `.config/container` configurations for fedora, ubuntu, arch, and custom image [podman systemd quadlets][podman-quadlets].
- quadlet dotfile management using [GNU Stow][gnu-stow]
- github actions for CI/CD for any image customizations
- documentation demonstrating how to set this up yourself and what the expected behavior should be

Feel free to adapt and use these customizations yourself -- this fork retains the [Apache License 2.0](./LICENSE) license of the [upstream repository][upstream]

## Overview

I think the primary raison-d'etre for this repository, and its upstream, is to address the following situation that I've often found myself in as an adopter of the Atomic Desktop paradigm:

1. you are using an atomic/immutable/etc. desktop OS (e.g. [Fedora Atomic Desktops][fedora-atomic-desktops] like [Silverblue][silverblue])
2. you are using [distroboxes][distrobox] as your mutable environments (day-to-day CLI for e.g.)
3. you want to maintain a set of customizations to these distroboxes without having to restart every time the container is deployed (e.g. package installations)
4. you want to automatically synchronize customizations to your distroboxes across multiple machines (a desktop and a laptop for e.g.)
5. you want your distroboxes to behave no worse than a normal CLI on a normal desktop OS (instant start up on login/reboot for just one e.g.)
6. you want visible, transparent, maintainable versioning of your distroboxes so you can rollback to a working version whenever you like (i.e. you want the benefits of the atomic desktop paradigm that you've spent so much time setting up!)

The upstream repository gestures at solutions to all of the above via the [`boxkit` template repository][boxkit] and sample `systemd` and `quadlet` unit definitions -- for understandable reasons, documentation for attaining a general cohesive setup using these templates does not seem to exist. I've spent enough time trying to band-aid my own non-working solutions that I've decided it's time to implement and document this process properly.

## Custom Images

In addition to the images defined in [ublue-os/toolboxes][upstream], this repository defines the following images:
- `cli` - a lean Wolfi base image that I would ostensibly use for day-to-day CLI, including [`nix`][nix] for a similar purpose to [Bluefin-CLI][bluefin-cli] including [`brew`][brew] -- that is, to fill out the "long tail" of existing software that is not yet packaged on `wolfi`.
- `cli-dx` - a larger Wolfi base image with additional developer packages, which is what I actually use for day-to-day CLI since I tend to develop things and want to have dependencies like `gcc` and `go` handy.

### Installing `nix`

TODO

- https://github.com/DeterminateSystems/nix-installer?tab=readme-ov-file#in-a-container
- https://gist.github.com/danmack/b76ef257e0fd9dda906b4c860f94a591#nix-package-manager-install-on-alpine-linux
- https://home-manager.dev/manual/23.05/index.html#sec-flakes-standalone

### Using `nix`

TODO

## Automatic Startup Configuration

The problem with customized images is that the customizations need to be applied at some point in time, which itself takes time. I would much rather time-consuming processes take place BEFORE I log into my system, so that the CLI environments I want to use can start instantly by the time I've logged in.

One way we can do this is to use [`systemd`][systemd] to start up-to-date distroboxes automatically when you log in. You could define the [`systemd.unit`][systemd-unit] files yourself, but the folks behind `podman` have set up [quadlets][podman-quadlets] which take care of some of the leg-work for you.

### Quadlets

1. Place quadlet files in `$XDG_CONFIG_HOME/containers/systemd`
2. Start the quadlet by using `systemctl start`
3. Enable the quadlet by default on boot using the `[Install]` unit file definition.

The steps below show how to do this.

You can find sample quadlet files in the `quadlets/` directory of this repo. You can automate the process of placing the quadlet files in the correct place using GNU `stow`; see the next section for that.

Once your files are placed correctly, generate a systemd service from the Quadlet file by reloading the systemd user daemon:

```
$ systemctl --user daemon-reload
```

Then, you should be able to start the service (and create the distrobox) and make sure the container is running. You can do this for all of the definitions I've provided, but let's take `arch-quadlet.service` for an example:

```
$ systemctl start --user arch-quadlet.service
$ podman ps
CONTAINER ID  IMAGE                                   COMMAND               CREATED         STATUS         PORTS       NAMES
81801de707b4  ghcr.io/ublue-os/arch-distrobox:latest  --verbose --name ...  24 seconds ago  Up 24 seconds              arch

$ distrobox list
ID           | NAME                 | STATUS             | IMAGE                         
81801de707b4 | arch                 | Up 55 seconds      | ghcr.io/ublue-os/arch-distrobox:latest
```

Finally, you can ensure that quadlet service starts on boot automatically by adding the following section to the `.container` file:

```
[Install]
WantedBy=default.target
```

For more information:

- https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
- https://www.redhat.com/sysadmin/podman-run-pods-systemd-services
- https://mo8it.com/blog/quadlet/

### Using `make` and `stow` to set up `.config/containers`

I've set up a `make` file with three different targets (`default`, `delete`, and `all`). These use `stow` to automate placing the quadlet definition files in the `~/.config/containers/systemd/` folder independent of where you place this repository. Run these commands from the root of this repository.

#### `make`

```
$ make
stow --verbose --target=$HOME --restow stowfiles/
LINK: .config/containers/systemd/fedora-distrobox-quadlet.container => ../../../opt/toolboxes/stowfiles/.config/containers/systemd/fedora-distrobox-quadlet.container
LINK: .config/containers/systemd/ubuntu-distrobox-quadlet.container => ../../../opt/toolboxes/stowfiles/.config/containers/systemd/ubuntu-distrobox-quadlet.container
LINK: .config/containers/systemd/wolfi-distrobox-quadlet.container => ../../../opt/toolboxes/stowfiles/.config/containers/systemd/wolfi-distrobox-quadlet.container
LINK: .config/containers/systemd/wolfi-dx-distrobox-quadlet.container => ../../../opt/toolboxes/stowfiles/.config/containers/systemd/wolfi-dx-distrobox-quadlet.container
```

#### `make delete`

This removes existing symlinks:

```
$ make delete
stow --verbose --target=$HOME --delete stowfiles/
UNLINK: .config/containers/systemd/fedora-distrobox-quadlet.container
UNLINK: .config/containers/systemd/ubuntu-distrobox-quadlet.container
UNLINK: .config/containers/systemd/wolfi-distrobox-quadlet.container
UNLINK: .config/containers/systemd/wolfi-dx-distrobox-quadlet.container
```

#### `make all`

This combines `make delete` and the default `make` command to replace existing symlinks:

```
$ make all
stow --verbose --target=$HOME --restow stowfiles/
UNLINK: .config/containers/systemd/fedora-distrobox-quadlet.container
UNLINK: .config/containers/systemd/ubuntu-distrobox-quadlet.container
UNLINK: .config/containers/systemd/wolfi-distrobox-quadlet.container
UNLINK: .config/containers/systemd/wolfi-dx-distrobox-quadlet.container
LINK: .config/containers/systemd/fedora-distrobox-quadlet.container => ../../../opt/toolboxes/stowfiles/.config/containers/systemd/fedora-distrobox-quadlet.container (reverts previous action)
LINK: .config/containers/systemd/ubuntu-distrobox-quadlet.container => ../../../opt/toolboxes/stowfiles/.config/containers/systemd/ubuntu-distrobox-quadlet.container (reverts previous action)
LINK: .config/containers/systemd/wolfi-distrobox-quadlet.container => ../../../opt/toolboxes/stowfiles/.config/containers/systemd/wolfi-distrobox-quadlet.container (reverts previous action)
LINK: .config/containers/systemd/wolfi-dx-distrobox-quadlet.container => ../../../opt/toolboxes/stowfiles/.config/containers/systemd/wolfi-dx-distrobox-quadlet.container (reverts previous action)
```

## Automatic Updates Configuration

Check if new images are available via `podman auto-update --dry-run`:

```
$ podman auto-update --dry-run
            UNIT                    CONTAINER              IMAGE                                   POLICY      UPDATED
            cli-quadlet.service     27045f00fb8e (cli)     ghcr.io/michaelhaaf/cli:latest          registry    pending
            cli-dx-quadlet.service  14bf4200f9b4 (cli-dx)  ghcr.io/michaelhaaf/cli-dx:latest       registry    pending
            arch-quadlet.service    1acbcfa3c350 (arch)    ghcr.io/ublue-os/arch-distrobox:latest  registry    pending
            fedora-quadlet.service  96b79aa599ca (fedora)  ghcr.io/ublue-os/fedora-toolbox:latest  registry    pending
            ubuntu-quadlet.service  9636bea3dd6e (ubuntu)  ghcr.io/ublue-os/ubuntu-toolbox:latest  registry    pending
```

If `UPDATED` is `pending`, then updates are available: update the images with `podman auto-update`. Successive `--dry-runs` will show that `UPDATED` is `false`, indicating that a run of `auto-update` would not update the image (so you have the latest version):

```
$ podman auto-update --dry-run
            UNIT                    CONTAINER              IMAGE                                   POLICY      UPDATED
            cli-quadlet.service     27045f00fb8e (cli)     ghcr.io/michaelhaaf/cli:latest          registry    false
            cli-dx-quadlet.service  14bf4200f9b4 (cli-dx)  ghcr.io/michaelhaaf/cli-dx:latest       registry    false
            arch-quadlet.service    1acbcfa3c350 (arch)    ghcr.io/ublue-os/arch-distrobox:latest  registry    false
            fedora-quadlet.service  96b79aa599ca (fedora)  ghcr.io/ublue-os/fedora-toolbox:latest  registry    false
            ubuntu-quadlet.service  9636bea3dd6e (ubuntu)  ghcr.io/ublue-os/ubuntu-toolbox:latest  registry    false
```

## Future improvements

- [Container save and restore](https://distrobox.it/useful_tips/#container-save-and-restore): to use with generic ubuntu/fedora/etc. images on particular projects; that way we have a default container built using the processes in this repo, and container customizations can be saved/restored in a programmatic way.

[upstream]: https://github.com/ublue-os/toolboxes
[nix]: https://nixos.org/download/
[brew]: https://brew.sh
[podman-quadlets]: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
[gnu-stow]: https://www.gnu.org/software/stow/
[distrobox]: https://distrobox.it/
[silverblue]: https://fedoraproject.org/atomic-desktops/silverblue/
[fedora-atomic-desktops]: https://fedoraproject.org/atomic-desktops/
[boxkit]: https://github.com/ublue-os/boxkit
[systemd]: https://systemd.io/
[systemd-unit]: https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html
[bluefin-cli]: https://universal-blue.discourse.group/t/the-bluefin-cli-container/704
