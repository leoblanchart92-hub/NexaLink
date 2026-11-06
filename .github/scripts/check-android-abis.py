"""Check actual archive contents, not just gomobile's requested targets."""
from zipfile import ZipFile

abis = ("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
with ZipFile("android/app/libs/nexalink-gateway.aar") as aar:
    entries = set(aar.namelist())
    for abi in abis:
        assert f"jni/{abi}/libgojni.so" in entries, f"missing Go AAR library: {abi}"
    print("Go AAR:", ", ".join(abis))
with ZipFile("build/app/outputs/flutter-apk/app-release.apk") as apk:
    entries = set(apk.namelist())
    present = [abi for abi in abis if f"lib/{abi}/libgojni.so" in entries]
    print("Release APK Go libraries:", ", ".join(present))
    for abi in ("arm64-v8a", "armeabi-v7a", "x86_64"):
        assert abi in present, f"missing Go release library: {abi}"
    # Flutter release builds generally omit 32-bit x86. Compilation of the AAR
    # does not prove that a release APK or runtime supports that ABI.
