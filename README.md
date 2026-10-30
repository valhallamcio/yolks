# yolks

Java images for Pterodactyl and Pelican game servers, with an Azul Zulu JDK. The ValhallaMC Minecraft servers run on
them. Each image is Azul's own `azul/zulu-openjdk` image, pinned by digest, plus the java yolk layout from
[pelican-eggs/yolks](https://github.com/pelican-eggs/yolks). Images: `ghcr.io/valhallamcio/yolks`.

## Tags

| moving tag | pinned tag | JDK | Azul base | CRaC |
|--|--|--|--|--|
| `java_8_zulu` | `java_8_zulu-8.98.0.107` | Zulu 8.98.0.107 (8u512) | `azul/zulu-openjdk:8u512-8.98` | no (Azul has no CRaC build for 8) |
| `java_17_zulu_crac` | `java_17_zulu_crac-17.68.203` | Zulu 17.68.203 (17.0.20.1) | `azul/zulu-openjdk:17.0.20.1-17.68-jdk-crac` | yes |
| `java_21_zulu_crac` | `java_21_zulu_crac-21.52.203` | Zulu 21.52.203 (21.0.12.1) | `azul/zulu-openjdk:21.0.12.1-21.52-jdk-crac` | yes |
| `java_25_zulu_crac` | `java_25_zulu_crac-25.36.205` | Zulu 25.36.205 (25.0.4.1) | `azul/zulu-openjdk:25.0.4.1-25.36-jdk-crac` | yes |

- The moving tag follows the newest build. A server on a moving tag gets a new JDK at its next start after a JDK bump.
- The pinned tag stays on one Zulu build. Use it where the exact JDK matters: CRaC image mode (a restore must run
  on the JVM build that made the image) and rollback.
- Each build also pushes `<pinned tag>-<commit sha>`. That tag is never reused.
- The Azul digests are in the matrix of `.github/workflows/build.yml`. The digest of each pushed image is in the
  summary of its workflow run.
- The CRaC builds carry the `warp` and `criu` engines. `-XX:CRaCEngine=warp` works in the Wings container shape
  (non-root, read-only root, no added capabilities). The smoke test checks a warp checkpoint and restore.

## Contract

The same as the pelican-eggs java yolks, so an egg that runs on `ghcr.io/parkervcp/yolks:java_25` runs here:

- `tini -g` is PID 1. `/entrypoint.sh` prints `java -version`, turns `{{VAR}}` into `${VAR}` in `STARTUP` and runs it
  with `eval`.
- `entrypoint.sh` is the pelican-eggs file without changes. tini is Ubuntu's `tini 0.19.0-1`. The build checks the
  sha256 of both against the bytes in `ghcr.io/parkervcp/yolks:java_25`.
- User `container`, workdir `/home/container`, `STOPSIGNAL SIGINT`.

Additions: `libnuma1` (for `-XX:+UseNUMA`), `jq`, the `en_US.UTF-8` locale, and `/opt/java/openjdk` as a link to the
versioned `JAVA_HOME`.

Java 25 logs `NUMA support disabled: Failed to initialize libnuma` in a container with Docker's default seccomp
profile, even with libnuma installed. The profile blocks the NUMA memory policy syscalls without `CAP_SYS_NICE`. The
Temurin 25 yolk logs the same line. The JVM starts and runs without NUMA.

java is a child of bash, not PID 1. `jcmd 1` does not reach the server JVM. Find its pid first, for example with
`docker top <container>`.

## Use it in the panel

Set the server's Docker image to `ghcr.io/valhallamcio/yolks:<tag>`. Wings pulls the image before each start. The
packages are public, so the nodes need no registry login. The change loads at the next start.

## Roll back

- Set the panel image back to the old value. It loads at the next start. Wings uses the node's cached copy of the old
  image when it cannot pull it.
- To go back to an older build of these images, use its pinned tag, its commit tag or its digest
  (`ghcr.io/valhallamcio/yolks@sha256:<digest>`).
- Flags that only one JVM accepts must change together with the image (for example OpenJ9 `-X` options, or Graal
  `-XX:+EagerJVMCI`).

## Bump a JDK

1. Find the new Azul tag and its digest:
   `docker buildx imagetools inspect azul/zulu-openjdk:<tag> --format '{{json .Manifest.Digest}}'`.
2. In `.github/workflows/build.yml`, edit `base` (tag and digest), `zulu` and `expect` of that image.
3. Push to main. The workflow builds, runs `test/smoke.sh` and pushes only when the test passes.
4. The old pinned tag stays in the registry.

Test one image locally:

```sh
docker build --build-arg ZULU_IMAGE=<base> --build-arg ZULU_EXPECT='<expect>' -t local/yolks:test .
bash test/smoke.sh local/yolks:test '<expect>' crac
```

## Known issue: CRaC and WatchService (Zulu 17.68, 21.52, 25.36)

`sun.nio.fs.LinuxWatchService.Poller.processCheckpointRestore` removes and puts `wdToKey` entries while it iterates
that map. When a `WatchService` holds 2 or more keys at checkpoint time, the poller thread dies with
`ConcurrentModificationException`, and `afterRestore` waits forever. The checkpoint then hangs, and a restore would
hang the same way. Minecraft mods hit it through config file watchers (night-config `FileWatcher`, the
supermartijn642 config lib, UnionLib).

These images ship Azul's JDK without changes. The workaround is a patched `LinuxWatchService` class that iterates a
copy of the map. Build it per JDK from that JDK's `src.zip`, and load it with `--patch-module java.base=<dir>` on the
JVM that makes the checkpoint. Put that flag only on a CRaC JVM: the patched class needs `jdk.internal.crac`.
A plain start without CRaC does not use this code.
