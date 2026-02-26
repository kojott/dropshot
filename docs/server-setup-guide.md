# Server Setup Guide

This guide walks you through setting up an SFTP server for use with DropShot. By the end, you will have a working upload directory that DropShot can write to, and optionally a web server to make uploaded files accessible via public URLs.

## Prerequisites

- A Linux server (Debian, Ubuntu, Fedora, Arch, or similar) with root or sudo access
- SSH access to the server
- A domain name (optional, only needed for public URL mode)

If you already have a server with SSH access, skip to [Option 1](#option-1-existing-server-with-ssh-access).

## Option 1: Existing Server with SSH Access

If you can already `ssh youruser@yourserver.com`, you are most of the way there. Skip ahead to [Creating the Upload Directory](#creating-the-upload-directory).

## Option 2: VPS Setup

If you do not have a server, a basic VPS from any provider will work. Here is a quick example using DigitalOcean or Hetzner.

### DigitalOcean

1. Create an account at [digitalocean.com](https://www.digitalocean.com/).
2. Create a Droplet:
   - **Image**: Ubuntu 24.04 LTS
   - **Plan**: Basic, $6/month (1 vCPU, 1 GB RAM, 25 GB SSD) is more than enough
   - **Region**: Choose the closest to you for fastest uploads
   - **Authentication**: Add your SSH key (see [SSH Key Setup](#ssh-key-setup) below)
3. Note the Droplet's IP address.

### Hetzner

1. Create an account at [hetzner.com](https://www.hetzner.com/).
2. Create a server:
   - **Image**: Ubuntu 24.04
   - **Type**: CX22 (2 vCPU, 4 GB RAM) or smaller
   - **Location**: Choose the closest to you
   - **SSH Key**: Add your public key during setup
3. Note the server's IP address.

### First connection

```bash
ssh root@YOUR_SERVER_IP
```

Create a non-root user for uploads (using root for daily SSH is not recommended):

```bash
# Create user
adduser dropshot

# Add to sudo group (optional, for administration)
usermod -aG sudo dropshot
```

## SSH Key Setup

DropShot works best with SSH key authentication. If you do not already have a key pair, generate one:

```bash
# ed25519 is recommended (fast, secure, short keys)
ssh-keygen -t ed25519 -C "dropshot@$(hostname)"
```

When prompted:
- **File**: Accept the default (`~/.ssh/id_ed25519`) or choose a custom path.
- **Passphrase**: Set a strong passphrase. DropShot works with ssh-agent, so you only need to enter it once per session.

Copy the public key to your server:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub youruser@yourserver.com
```

Verify passwordless login:

```bash
ssh youruser@yourserver.com
```

### Using 1Password SSH Agent

If you use 1Password to manage your SSH keys, DropShot supports the 1Password SSH agent. Configure the 1Password SSH agent following [1Password's documentation](https://developer.1password.com/docs/ssh/agent/) and DropShot will use it automatically.

## Creating the Upload Directory

SSH into your server and create a directory for uploads:

```bash
# Choose a path -- this is what you will enter in DropShot's preferences
sudo mkdir -p /srv/uploads

# Set ownership to your upload user
sudo chown youruser:youruser /srv/uploads

# Set permissions (owner can read/write/list, others can only read/list)
sudo chmod 755 /srv/uploads
```

Verify you can write to it:

```bash
touch /srv/uploads/test.txt && rm /srv/uploads/test.txt
echo "Upload directory is working."
```

### Directory structure tips

- Use `/srv/uploads/` for a clean, standard location.
- If serving files publicly, keep the web root and upload directory aligned (e.g. nginx serves `/srv/uploads/` at `https://files.example.com/`).
- Consider a separate partition or disk quota if you are concerned about disk space.

## Optional: Serving Files Publicly with nginx

If you want DropShot to copy public URLs instead of server paths, you need a web server to serve the upload directory.

### Install nginx

```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y nginx

# Fedora
sudo dnf install -y nginx
```

### Configure nginx

Create a site configuration:

```bash
sudo tee /etc/nginx/sites-available/dropshot <<'NGINX'
server {
    listen 80;
    server_name files.example.com;

    root /srv/uploads;
    autoindex off;

    location / {
        try_files $uri =404;

        # Security headers
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;
        add_header Content-Security-Policy "default-src 'none'" always;

        # Serve files with correct MIME types
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
    }
}
NGINX
```

Enable the site and restart nginx:

```bash
sudo ln -s /etc/nginx/sites-available/dropshot /etc/nginx/sites-enabled/
sudo nginx -t          # Verify configuration
sudo systemctl restart nginx
sudo systemctl enable nginx
```

### Add HTTPS with Let's Encrypt

Public file serving should always use HTTPS:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d files.example.com
```

Certbot will automatically configure nginx to use HTTPS and set up auto-renewal.

### Configure DropShot

In DropShot's preferences, set:
- **Remote Path**: `/srv/uploads/`
- **Base URL**: `https://files.example.com/`

Now when you upload a file, DropShot will copy `https://files.example.com/screenshot.png` to your clipboard instead of `/srv/uploads/screenshot.png`.

### Alternative: Apache

If you prefer Apache:

```bash
sudo apt install -y apache2

sudo tee /etc/apache2/sites-available/dropshot.conf <<'APACHE'
<VirtualHost *:80>
    ServerName files.example.com
    DocumentRoot /srv/uploads

    <Directory /srv/uploads>
        Options -Indexes -FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "DENY"
</VirtualHost>
APACHE

sudo a2enmod headers
sudo a2ensite dropshot
sudo systemctl restart apache2
```

## Testing with the `sftp` Command

Before configuring DropShot, verify everything works with the standard `sftp` command:

```bash
# Connect
sftp youruser@yourserver.com

# Navigate to the upload directory
cd /srv/uploads

# Upload a test file
put /tmp/test.txt

# Verify it arrived
ls -la test.txt

# Clean up
rm test.txt

# Disconnect
exit
```

If using a non-standard port:

```bash
sftp -P 2222 youruser@yourserver.com
```

## Troubleshooting

### "Permission denied" when uploading

```bash
# Check directory ownership
ls -la /srv/ | grep uploads

# Fix ownership
sudo chown youruser:youruser /srv/uploads

# Check directory permissions (need write for owner)
sudo chmod 755 /srv/uploads
```

### "Connection refused"

- Verify SSH is running: `sudo systemctl status sshd`
- Check the port: `sudo ss -tlnp | grep ssh`
- Check the firewall: `sudo ufw status` (Ubuntu) or `sudo firewall-cmd --list-all` (Fedora)

### "Host key verification failed"

This means the server's SSH host key has changed since you last connected. This can happen after a server reinstall. If you trust the change:

```bash
# Remove the old key
ssh-keygen -R yourserver.com

# Connect again and accept the new key
ssh youruser@yourserver.com
```

DropShot will also show a warning dialog when it detects a host key mismatch.

### SSH key not accepted

```bash
# Verify key permissions (must be 600 or more restrictive)
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# Verify the public key is in authorized_keys on the server
cat ~/.ssh/id_ed25519.pub
# Then on the server:
cat ~/.ssh/authorized_keys
# The public key should appear as a line in this file

# Verify the .ssh directory permissions on the server
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### "SFTP subsystem failed"

The SSH server needs the SFTP subsystem enabled. Check the SSH configuration:

```bash
grep -i sftp /etc/ssh/sshd_config
```

You should see a line like:

```
Subsystem sftp /usr/lib/openssh/sftp-server
```

If it is commented out or missing, add it and restart SSH:

```bash
sudo systemctl restart sshd
```

### Files upload but nginx returns 403

```bash
# Check that nginx can read the files
sudo -u www-data test -r /srv/uploads/test.txt && echo "OK" || echo "Cannot read"

# Fix: add the nginx user to the upload user's group
sudo usermod -aG youruser www-data
sudo systemctl restart nginx
```

### Slow uploads

- Check your upload bandwidth: `curl -o /dev/null -w "%{speed_upload}" -T /tmp/testfile sftp://yourserver.com/srv/uploads/testfile`
- Consider a server closer to your location.
- Large files (100 MB+) are limited by your upstream bandwidth, not DropShot.

## Security Considerations

- **Do not use root** for uploads. Create a dedicated user with minimal permissions.
- **Use SSH keys** instead of passwords. Disable password authentication in `/etc/ssh/sshd_config` if possible:
  ```
  PasswordAuthentication no
  ```
- **Use a firewall** to limit SSH access to your IP if possible.
- **Keep your server updated**: `sudo apt update && sudo apt upgrade -y`
- **Disable directory listings** in nginx (`autoindex off`) to prevent people from browsing your uploads.
- **Consider access control** if uploads should not be publicly accessible. You can use nginx `auth_basic`, IP restrictions, or simply skip the web server setup and use server paths only.
- **Set up fail2ban** to protect against brute-force SSH attacks:
  ```bash
  sudo apt install -y fail2ban
  sudo systemctl enable fail2ban
  ```
- **Monitor disk usage** to avoid filling up your server. Set up a cron job or monitoring alert.
