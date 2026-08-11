# CUDA Setup on Fedora

A fresh-install guide for getting an NVIDIA GPU driver, CUDA runtime, and
(optionally) the full CUDA Toolkit working on Fedora.

## What you're actually installing

Three separate layers, often conflated:

1. **GPU driver** (kernel module + display driver) — lets the OS see and use
   the GPU at all.
2. **CUDA runtime** (`libcuda.so`, `nvidia-smi`, NVML) — lets already-built
   CUDA programs run (PyTorch, llama.cpp, most ML tooling bundle their own
   CUDA runtime and only need this + the driver).
3. **CUDA Toolkit** (`nvcc`, headers, dev libraries) — needed only if you're
   compiling CUDA C/C++ code yourself.

Most people doing ML/AI work only need #1 and #2.

## Fresh install

### 1. Enable RPM Fusion

Fedora's own repos ship only the open-source `nouveau` driver. The proprietary
NVIDIA driver comes from RPM Fusion, not Fedora itself.

```bash
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                     https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

### 2. Install the driver

```bash
dnf search xorg-x11-drv-nvidia          # check what's actually on offer first
sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs \
                     nvidia-settings nvidia-modprobe
akmods --status                          # wait until it reports built for your kernel
sudo reboot
```

RPM Fusion sometimes publishes multiple driver series in parallel (e.g. a
versioned `xorg-x11-drv-nvidia-XXXyy` alongside — or instead of — the
unsuffixed package), targeting different GPU generations. Always `dnf search`
first rather than assuming the unsuffixed name exists.

### 3. Install the CUDA runtime + `nvidia-smi`

```bash
sudo dnf install -y xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-libs
```

Use the same suffix (if any) that step 2 resolved to, e.g.
`xorg-x11-drv-nvidia-XXXyy-cuda`.

### 4. (Optional) Full CUDA Toolkit — only if you need `nvcc`

NVIDIA publishes a Fedora-version-specific repo:

```text
https://developer.download.nvidia.com/compute/cuda/repos/fedora<N>/x86_64/
```

```bash
sudo dnf config-manager addrepo --from-repofile=https://developer.download.nvidia.com/compute/cuda/repos/fedora<N>/x86_64/cuda-fedora<N>.repo
sudo dnf install -y cuda-toolkit --exclude="nvidia-driver*,nvidia-driver-cuda-libs*"
```

Two things to watch for here:

- **Driver conflict**: this repo also ships its own `nvidia-driver` package,
  which owns the same files as the RPM Fusion driver. Installing the toolkit
  without excluding it can silently swap out your working driver and break
  the display on reboot — always `--exclude` as shown above.
- **Compiler version**: `nvcc` only supports host `gcc` versions up to some
  point behind current. If Fedora's default `gcc` is too new for the CUDA
  version you're installing, install an older one side-by-side (don't change
  the system default) and point `nvcc` at it:

  ```bash
  sudo dnf install -y gcc13 gcc13-c++
  nvcc -ccbin /usr/bin/gcc-13 ...
  ```

## Verifying the install

```bash
lspci -nnk | grep -iE "vga|3d|nvidia" -A3            # GPU present, "Kernel driver in use: nvidia"
lsmod | grep -i nvidia                                # nvidia, nvidia_drm, nvidia_modeset, nvidia_uvm loaded
nvidia-smi                                            # driver version, max-supported CUDA version, GPU status
nvidia-smi -L                                         # just the GPU name/UUID, quick sanity check
ldconfig -p | grep -iE "libcuda.so|libnvidia-ml.so"   # runtime libs are linkable
nvcc --version                                        # actual toolkit version (only if step 4 was done)
```

Note: the CUDA version `nvidia-smi` prints is the **maximum version the
driver supports**, not necessarily what's installed — `nvcc --version` is the
source of truth for the toolkit itself.

On laptops with hybrid graphics (NVIDIA + AMD/Intel integrated), also check
`lspci -nnk` for the integrated GPU's line to confirm which one the display is
actually running on — the driver can be loaded and functional while the
desktop is still rendering through the other GPU.

## Coming from Ubuntu?

The main differences:

- Ubuntu ships the proprietary driver directly (`apt install nvidia-driver-XXX`,
  or `ubuntu-drivers autoinstall`); Fedora doesn't — RPM Fusion is required first.
- Ubuntu's DKMS rebuilds kernel modules automatically on kernel updates;
  Fedora's equivalent is `akmods` — if the driver stops loading after a kernel
  update, check `akmods --status` before anything else.
- Package names don't map 1:1: `nvidia-driver-550` / `nvidia-cuda-toolkit`
  (Ubuntu) vs. `akmod-nvidia` / `xorg-x11-drv-nvidia*` / `cuda-toolkit` (Fedora).
- NVIDIA's official CUDA Toolkit repo/installer supports both distros
  directly — the same driver-conflict hazard from step 4 applies on Ubuntu
  too, just with `apt` instead of `dnf`.

## Resources

- RPM Fusion NVIDIA driver howto: <https://rpmfusion.org/Howto/NVIDIA>
- NVIDIA CUDA downloads (official): <https://developer.nvidia.com/cuda-downloads>
- NVIDIA CUDA repo index (browse available distro/version combos): <https://developer.download.nvidia.com/compute/cuda/repos/>
- NVIDIA CUDA Installation Guide for Linux: <https://docs.nvidia.com/cuda/cuda-installation-guide-linux/>
