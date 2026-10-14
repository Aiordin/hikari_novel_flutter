{
  description = "Hikari Novel：可复现的 Android 构建 + waydroid 验证环境";

  # 用 flake registry 里的 nixpkgs；`nix flake lock` 后即固定到具体 rev。
  inputs.nixpkgs.url = "nixpkgs";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          # nixpkgs 的 androidenv 需要显式接受 SDK license。
          android_sdk.accept_license = true;
          allowUnfree = true;
        };
      };

      flutter = pkgs.flutter;
      jdk = pkgs.jdk21;

      # Android SDK 组件，版本对齐 flutter 的 compileSdkVersion / ndkVersion。
      # 多给一个 build-tools 版本，避免 AGP 因找不到而尝试联网下载（SDK 目录只读）。
      androidSdk =
        (pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "latest";
          platformToolsVersion = "latest";
          # 插件的 compileSdk 各自独立，不是 flutter 一个值就能覆盖：
          #   charset_converter / flutter_mailer → 34
          #   jni / sqlite3_flutter_libs        → 35
          #   flutter_tts / fluttertoast        → 36
          # 缺哪个，AGP 就会尝试联网下载到只读的 SDK 目录并失败。
          buildToolsVersions = [
            "34.0.0"
            "35.0.0"
            "36.0.0"
            "36.1.0"
          ];
          platformVersions = [
            "34"
            "35"
            "36"
          ];
          includeNDK = true;
          # 与 flutter 3.47 的 FlutterExtension.ndkVersion 一致。
          ndkVersions = [ "28.2.13676358" ];
          # jni 插件走 externalNativeBuild.cmake（未钉版本，用 AGP 默认）。
          # 不同 AGP 默认值不同（3.10.2 / 3.22.1 / 3.31.x），一并提供。
          includeCmake = true;
          cmakeVersions = [
            "3.10.2"
            "3.22.1"
            "3.31.4"
          ];
          includeEmulator = false;
          includeSystemImages = false;
          includeSources = false;
        }).androidsdk;

      sdkRoot = "${androidSdk}/libexec/android-sdk";

      androidEnv = {
        ANDROID_HOME = sdkRoot;
        ANDROID_SDK_ROOT = sdkRoot;
        ANDROID_JAVA_HOME = "${jdk.home}";
        JAVA_HOME = "${jdk.home}";
      };

      toolchain = [
        flutter
        jdk
        androidSdk
        pkgs.coreutils
        pkgs.which
        pkgs.git
        pkgs.unzip
        pkgs.curl
      ];

      # 构建 APK。以 `nix run .#build-apk [项目目录]` 执行：
      # 在用户环境（有网络）里跑 gradle / pub get，SDK 与 JDK 来自 nix。
      #
      # 内存限制：项目自带的 android/gradle.properties 写的是
      # `-Xmx8G -XX:MaxMetaspaceSize=4G`，在本机（14G、无 swap）上会挤爆内存。
      # 这里覆盖为受控值，并叠加 cgroup 硬上限。可用环境变量覆盖：
      #   HIKARI_BUILD_MEMORY    cgroup MemoryMax（默认 6G）
      #   HIKARI_BUILD_JVM_HEAP  Gradle -Xmx（默认 2g）
      #   HIKARI_BUILD_WORKERS   Gradle 并发 worker（默认 4）
      build-apk = pkgs.writeShellApplication {
        name = "build-apk";
        runtimeInputs = toolchain ++ [ pkgs.systemd ];
        text = ''
          export ANDROID_HOME=${sdkRoot}
          export ANDROID_SDK_ROOT=${sdkRoot}
          export ANDROID_JAVA_HOME=${jdk.home}
          export JAVA_HOME=${jdk.home}

          # 这些变量必须 export：下面用 `bash -c "$(declare -f build); build"`
          # 在 systemd-run 的子 shell 里重建函数，普通变量不会随函数定义过去。
          export project="''${1:-.}"
          export memory_max="''${HIKARI_BUILD_MEMORY:-6G}"
          export jvm_heap="''${HIKARI_BUILD_JVM_HEAP:-2g}"
          export workers="''${HIKARI_BUILD_WORKERS:-4}"

          build() {
            cd "$project"

            # -D 系统属性优先于 gradle.properties，用来盖掉项目里的 -Xmx8G。
            export GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx$jvm_heap -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError -Dorg.gradle.workers.max=$workers ''${GRADLE_OPTS:-}"

            echo "== 资源限制：cgroup MemoryMax=$memory_max / Gradle -Xmx$jvm_heap / workers=$workers =="
            echo "== flutter 版本 =="
            flutter --version
            echo "== 构建 debug APK =="
            flutter pub get
            # cronetHttpNoPlay=true：改用 embedded Cronet（单一 AAR）。用默认的
            # play-services-cronet 时，它的 cronet-api / cronet-shared 两个 AAR
            # 共用 namespace org.chromium.net，会被 AGP 的 namespace 校验挡下。
            flutter build apk --debug --dart-define=cronetHttpNoPlay=true
            echo "== 产物 =="
            ls -l build/app/outputs/flutter-apk/*.apk
          }

          if command -v systemd-run >/dev/null 2>&1 \
             && systemd-run --user --scope --quiet -p MemoryMax="$memory_max" -p MemorySwapMax=0 true >/dev/null 2>&1; then
            # cgroup 硬上限：超限由内核处理，不会把整机拖垮。
            systemd-run --user --scope --quiet \
              -p MemoryMax="$memory_max" \
              -p MemorySwapMax=0 \
              -- bash -c "''$(declare -f build); build"
          else
            echo "警告：systemd-run --user 不可用，只设 JVM 堆上限（无 cgroup 硬限制）" >&2
            build
          fi
        '';
      };

      # 把已构建的 APK 装进正在运行的 waydroid 并启动。
      waydroid-test = pkgs.writeShellApplication {
        name = "waydroid-test";
        runtimeInputs = [
          pkgs.waydroid
          pkgs.android-tools
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gawk
        ];
        text = ''
          apk="''${1:?用法: waydroid-test <apk 路径>}"
          if [ ! -f "$apk" ]; then
            echo "找不到 APK：$apk" >&2
            exit 1
          fi

          # waydroid session 是用户态服务；未运行时拉起它。
          if ! waydroid status | grep -q 'Session:.*RUNNING'; then
            echo "== 启动 waydroid session =="
            waydroid session start &
            for _ in $(seq 1 30); do
              waydroid status | grep -q 'Session:.*RUNNING' && break
              sleep 1
            done
          fi

          waydroid status

          ip="$(waydroid status | awk -F'\t' '/IP address/{print $2}')"
          : "''${ip:=192.168.240.112}"
          echo "== adb 连接 $ip:5555 =="
          adb connect "$ip:5555" || true
          # 明确指定设备：接上 USB 真机后，不带 -s 的 adb 会产生歧义。
          adb -s "$ip:5555" wait-for-device

          echo "== 安装 $apk =="
          adb -s "$ip:5555" install -r "$apk"

          echo "== 启动 App =="
          adb -s "$ip:5555" shell am start -n pers.cyh128.hikari_novel/.MainActivity
          echo "== 已启动；用 adb logcat 观察运行日志 =="
        '';
      };

      # 把 APK 装到通过 USB 连接的真机（或任意 adb 设备）并启动。
      device-test = pkgs.writeShellApplication {
        name = "device-test";
        runtimeInputs = [
          pkgs.android-tools
          pkgs.coreutils
          pkgs.gnugrep
        ];
        text = ''
          apk="''${1:-build/app/outputs/flutter-apk/app-debug.apk}"
          if [ ! -f "$apk" ]; then
            echo "找不到 APK：$apk" >&2
            exit 1
          fi

          echo "== 已连接设备 =="
          adb devices -l

          mapfile -t serials < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
          if [ "''${#serials[@]}" -eq 0 ]; then
            echo "没有处于 device 状态的设备；真机需先打开 USB 调试并授权本机。" >&2
            exit 1
          fi

          for s in "''${serials[@]}"; do
            echo "== 安装到 $s =="
            adb -s "$s" install -r "$apk" || { echo "安装到 $s 失败" >&2; continue; }
            echo "== 启动 $s =="
            adb -s "$s" shell am start -n pers.cyh128.hikari_novel/.MainActivity
            echo "== 日志：adb -s $s logcat -s flutter =="
          done
        '';
      };
    in
    {
      devShells.${system} = {
        default = pkgs.mkShell (
          androidEnv
          // {
            packages = toolchain;
            shellHook = ''
              echo "hikari_novel_flutter dev shell"
              echo "  flutter : $(command -v flutter)"
              echo "  ANDROID_HOME : $ANDROID_HOME"
              echo "  JAVA_HOME : $JAVA_HOME"
            '';
          }
        );

        # 只跑 `flutter analyze` / `flutter test` 时用这个：
        # 不含 Android SDK，首次进入快得多。
        dart = pkgs.mkShell {
          packages = [
            flutter
            pkgs.git
          ];
        };
      };

      apps.${system} = {
        build-apk = {
          type = "app";
          program = "${build-apk}/bin/build-apk";
        };
        waydroid-test = {
          type = "app";
          program = "${waydroid-test}/bin/waydroid-test";
        };
        device-test = {
          type = "app";
          program = "${device-test}/bin/device-test";
        };
        default = self.apps.${system}.build-apk;
      };
    };
}
