# Function Templates — management function code templates

## Symbolic Link Initialization Function

Add to `bash/app/<app>.bash`:

```bash
<app>_init() {
    local source="$HOME/dotfiles/bash/<category>/<filename>"
    local target="<target_file>"

    echo "Initializing <app> configuration..."

    # Create directory if needed
    if [[ ! -d "$(dirname "$target")" ]]; then
        echo "Creating $(dirname "$target") directory..."
        mkdir -p "$(dirname "$target")"
    fi

    # Handle symbolic link
    if [[ -L "$target" ]]; then
        echo "<filename> symbolic link already exists"
    elif [[ -f "$target" ]]; then
        echo "<filename> exists as regular file"
        echo "Backing up to <filename>.backup..."
        mv "$target" "$target.backup"
        ln -s "$source" "$target"
        echo "Created symbolic link for <filename>"
    else
        ln -s "$source" "$target"
        echo "Created symbolic link for <filename>"
    fi

    echo ""
    echo "<app> configuration initialization complete!"
    echo ""
    echo "Symbolic link:"
    ls -la "$target"
}
```

## Configuration Editing Function (optional)

```bash
<app>_edit_<config>() {
    local config_file="$HOME/dotfiles/bash/<category>/<filename>"

    if [[ ! -f "$config_file" ]]; then
        echo "Config file not found: $config_file"
        return 1
    fi

    echo "Editing <app> configuration..."
    echo "File: $config_file"
    echo ""

    ${EDITOR:-vim} "$config_file"

    echo ""
    echo "Configuration file edited"
    echo "Changes will take effect immediately (symlinked)"
}
```

## Help Documentation Block

Add to `<app>help` function:

```bash
${bold}${blue}[Configuration Management]${reset}

  ${green}<app>_init${reset}         : <app> 설정 파일 symbolic link 초기화
                        (dotfiles/bash/<category>/<filename> ↔ <target_file>)
  ${green}<app>_edit_<config>${reset} : <filename> 파일 편집
```
