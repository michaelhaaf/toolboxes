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

This container uses `nix-daemon` to provide a non-root user `nix` runtime environment. The following steps are needed:

1. Install `nix` using the [determinate systems nix installer][determinate-systems]:

```
# Containerfile.cli
RUN curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux \
    --extra-conf "sandbox = false" \
    --init none \
    --no-confirm
ENV PATH="${PATH}:/nix/var/nix/profiles/default/bin"
```

This creates the normal `nix` installation directory in `/nix` on the container.

2. Ensure the default user on your system has access to `/nix/var/nix/daemon-socket`
```
# Containerfile.cli
RUN addgroup -g 1000 -S 1000 && adduser -u 1000 -S 1000 -G 1000 && \
    chgrp 1000 /nix/var/nix/daemon-socket && \
    chmod ug=rwx,o= /nix/var/nix/daemon-socket && \
    chmod a+rx /etc/init.d/nix-daemon
```
When `nix-daemon` is running, users can make requests to `nix-daemon` via this socket. It is probably dangerous to let just any user access the socket, so I'm using a group permissions setting to keep access limited.

3. Run `nix-daemon` on container start-up

Since alpine/wolfi-os do not have `systemd`, you need to start the daemon yourself. 

```
# 00-cli-firstrun.sh
  if test ! -d /nix/var/log/nix-daemon; then
    printf "Starting nix-daemon...\t\t\t "
    sudo mkdir -p /nix/var/log/nix-daemon/
    sudo nix-daemon 2>&1 | sudo tee "/nix/var/log/nix-daemon/$(date -I seconds).log" > /dev/null & disown
    printf "%s[ OK ]%s\n" "${blue}" "${normal}"
  fi
```

This probably could be done using `openrc` instead of a disowned shell process, but I couldn't get `openrc` to work. I might try again later.

#### References

- https://github.com/DeterminateSystems/nix-installer?tab=readme-ov-file#in-a-container
- https://gist.github.com/danmack/b76ef257e0fd9dda906b4c860f94a591#nix-package-manager-install-on-alpine-linux
- https://home-manager.dev/manual/23.05/index.html#sec-flakes-standalone
- https://nix.dev/manual/nix/2.18/installation/multi-user

### Using `nix`

This example uses `home-manager` to manage package installations. Your packages will be built directly on the host's `/home` directory, so re-builds won't be necessary when the container starts/stops.

#### TODO

It's not actually true that packages are built in `/home/` in the current state of this repository -- they're build in `/nix/store` and are therefore wiped with each container update.

Ideas:

- install nix somewhere other than `/nix`. See:
  - https://nixos.wiki/wiki/Storage_optimization#Moving_the_store
- have a nix store server that this container can pull when created. See:
  - https://yrh.dev/blog/nix-in-custom-location/ for a general overview/example
  - https://nix.dev/manual/nix/2.24/package-management/ssh-substituter.html if i'm selfhosting the nix store
  - https://discourse.nixos.org/t/recommendations-for-introducing-a-shared-nix-store-or-cache-for-ci-cd-and-development/15248/2 for explanation of the above
  - this flox thing? https://discourse.nixos.org/t/recommendations-for-introducing-a-shared-nix-store-or-cache-for-ci-cd-and-development/15248/4
  - 

#### References

- https://juliu.is/tidying-your-home-with-nix/

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

## Image Update Management

CLI for manual updates using `podman auto update`, [confusing the audience][ben-finegold-confusing-the-audience]. `systemd` services for automating the update/refresh of container images.

### Manual updates with CLI

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

### Automation with `systemd`

TODO

From the [podman auto-update docs][podman-auto-update]:

> To configure a container for auto updates, it must be created with the `io.containers.autoupdate` label or the `AutoUpdate` field in quadlet(5) with one of the following two values:
>
>    `registry`: If the label is present and set to registry, Podman reaches out to the corresponding registry to check if the image has been updated. The label image is an alternative to registry maintained for backwards compatibility. An image is considered updated if the digest in the local storage is different than the one of the remote image. If an image must be updated, Podman pulls it down and restarts the systemd unit executing the container. The registry policy requires a fully-qualified image reference (e.g., quay.io/podman/stable:latest) to be used to create the container. This enforcement is necessary to know which image to actually check and pull. If an image ID was used, Podman would not know which image to check/pull anymore.
>
>    `local`: If the autoupdate label is set to local, Podman compares the image digest of the container to the one in the local container storage. If they differ, the local image is considered to be newer and the systemd unit gets restarted.

The images in this repository use `registry` for the `AutoUpdate` field by default.

Furthermore: 

> After a successful update of an image, the containers using the image get updated by restarting the systemd units they run in.
>
> Podman ships with a `podman-auto-update.service` systemd unit. This unit is triggered daily at midnight by the `podman-auto-update.timer` systemd timer. The timer can be altered for custom time-based updates if desired. The unit can further be invoked by other systemd units (e.g., via the dependency tree) or manually via `systemctl start podman-auto-update.service`.

You can make sure this is happening by running commands such as `systemctl status --user podman-auto-update.service`. If inactive, it can be enabled and started using `systemctl enable` and `systemctl start`.

## Future improvements

- [Container save and restore](https://distrobox.it/useful_tips/#container-save-and-restore): to use with generic ubuntu/fedora/etc. images on particular projects; that way we have a default container built using the processes in this repo, and container customizations can be saved/restored in a programmatic way.
- [Podman image rollbacks](https://www.redhat.com/sysadmin/podman-auto-updates-rollbacks): probably should try this out and document it before I run into issues, but who am I kidding.

[upstream]: https://github.com/ublue-os/toolboxes
[nix]: https://nixos.org/download/
[brew]: https://brew.sh
[podman-quadlets]: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
[podman-auto-update]: https://docs.podman.io/en/latest/markdown/podman-auto-update.1.html
[gnu-stow]: https://www.gnu.org/software/stow/
[distrobox]: https://distrobox.it/
[silverblue]: https://fedoraproject.org/atomic-desktops/silverblue/
[fedora-atomic-desktops]: https://fedoraproject.org/atomic-desktops/
[boxkit]: https://github.com/ublue-os/boxkit
[systemd]: https://systemd.io/
[systemd-unit]: https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html
[bluefin-cli]: https://universal-blue.discourse.group/t/the-bluefin-cli-container/704
[ben-finegold-confusing-the-audience]: https://www.youtube.com/watch?v=qVt6nglrmh4
[determinate-systems]: https://install.determinate.systems/nix
