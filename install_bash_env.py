#!/usr/bin/env python3
import os
import sys
from pathlib import Path

# Single Responsibility Principle (SRP)
# The Colors class is now solely responsible for handling terminal colors.
class Colors:
    _OKBLUE = "\033[94m"
    _OKGREEN = "\033[92m"
    _WARNING = "\033[93m"
    _FAIL = "\033[91m"
    _ENDC = "\033[0m"

    @classmethod
    def blue(cls, text):
        return f"{cls._OKBLUE}{text}{cls._ENDC}"

    @classmethod
    def green(cls, text):
        return f"{cls._OKGREEN}{text}{cls._ENDC}"

    @classmethod
    def warning(cls, text):
        return f"{cls._WARNING}{text}{cls._ENDC}"

    @classmethod
    def fail(cls, text):
        return f"{cls._FAIL}{text}{cls._ENDC}"

# Single Responsibility Principle (SRP)
# This class is responsible for defining paths and target files.
class DotfilesConfig:
    HOME = Path.home()
    DOTFILES_DIR = HOME / "dotfiles/bash"
    TARGET_FILES = [
        ".bashrc",
        ".bash_profile",
        ".bash_alias",
        ".bash_application",
        ".bash_arm",
        ".bash_directory",
        ".bash_env_var",
        ".bash_git",
        ".bash_main",
        ".bash_python",
    ]

# Single Responsibility Principle (SRP)
# This class is solely responsible for the linking logic.
# Open/Closed Principle (OCP)
# The linking process is encapsulated. If we want to change how links are made (e.g.,
# copy instead of link), we can modify this class without affecting other parts.
class DotfileLinker:
    def __init__(self, config: DotfilesConfig):
        self.home = config.HOME
        self.dotfiles_dir = config.DOTFILES_DIR
        self.target_files = config.TARGET_FILES

    def link_dotfiles(self):
        print(Colors.blue("🔗 심볼릭 링크 생성 시작..."))
        for filename in self.target_files:
            target = self.home / filename
            source = self.dotfiles_dir / filename

            self._create_link(source, target)

    # Liskov Substitution Principle (LSP)
    # This method can be overridden by subclasses if different linking behavior
    # is required, without breaking the `link_dotfiles` method.
    # It also adheres to Interface Segregation Principle (ISP) by providing
    # a focused operation.
    def _create_link(self, source: Path, target: Path):
        if target.exists() or target.is_symlink():
            print(Colors.warning(f"⚠️  기존 파일 제거: {target}"))
            target.unlink()

        if source.exists():
            target.symlink_to(source)
            print(Colors.green(f"✅ 링크됨: {target} → {source}"))
        else:
            print(Colors.warning(f"⚠️  소스 파일 없음 (건너뜀): {source}"))

# Single Responsibility Principle (SRP)
# The DotfilesManager is responsible for orchestrating the overall dotfile management process.
# Dependency Inversion Principle (DIP)
# The DotfilesManager depends on abstractions (DotfilesConfig, DotfileLinker) rather than
# concrete implementations. This allows for easier testing and flexibility.
class DotfilesManager:
    def __init__(self, config: DotfilesConfig, linker: DotfileLinker):
        self.config = config
        self.linker = linker

    def run(self):
        if not self.config.DOTFILES_DIR.exists():
            print(Colors.fail(f"❌ dotfiles 디렉토리 없음: {self.config.DOTFILES_DIR}"))
            sys.exit(1)

        self.linker.link_dotfiles()
        print(Colors.blue("🎉 모든 링크 작업 완료"))

def main():
    config = DotfilesConfig()
    linker = DotfileLinker(config)
    manager = DotfilesManager(config, linker)
    manager.run()

if __name__ == "__main__":
    main()