# File Sharing (Samba)

CyberDeck shares the web dashboard files via SMB so you can edit HTML, CSS,
and JS directly from Windows, Mac, or Linux.

## Share Details

| Property  | Value                     |
|-----------|---------------------------|
| Share     | `webfiles`                |
| Path      | `/var/www/html`           |
| User      | `pi`                      |
| Protocol  | SMB (ports 139, 445)      |

## Connecting

### Windows
Open File Explorer and type in the address bar:
```
\\192.168.4.1\webfiles
```
Enter username `pi` and the Samba password you set during setup.

### macOS
Finder → Go → Connect to Server (Cmd+K):
```
smb://192.168.4.1/webfiles
```

### Linux
```bash
# Browse
smbclient //192.168.4.1/webfiles -U pi

# Mount
sudo mount -t cifs //192.168.4.1/webfiles /mnt/cyberdeck \
  -o username=pi,password=YOUR_PASS,uid=$(id -u),gid=$(id -g)
```

## How It Works

The `webfiles` share maps to `/var/www/html`, which nginx serves. Any file
you create or edit via SMB is immediately visible at `http://192.168.4.1/`.

File permissions use the `webedit` group with setgid, so both Samba writes
(as `pi`) and nginx reads (as `www-data`) work without conflicts.

## Changing the Samba Password

```bash
sudo smbpasswd pi
```

## Future: USB Drive Share

The Samba config has a placeholder for a USB drive share at `/mnt/usb`.
When USB storage is added in a future version, uncomment the `[storage]`
section in `/etc/samba/smb-cyberdeck.conf`.
