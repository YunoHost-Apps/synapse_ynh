# Installation

## Install for ARM arch (or slow arch)

For all slow or arm architecture it's recommended to build the dh file before the install to have a quicker install.
You could build it by this cmd : `openssl dhparam -out /etc/ssl/private/dh2048.pem 2048 > /dev/null`
After that you can install it without problem.

The package uses a prebuilt python virtual environnement. The binary are taken from this repository: <https://github.com/YunoHost-Apps/synapse_python_build>
The script to build the binary is also available.

## Web client

If you want a web client you can also install Element with this package: <https://github.com/YunoHost-Apps/element_ynh> .

## Access by federation

If your server name is identical to the domain on which synapse is installed, and the default port 8448 is used, your server is normally already accessible by the federation.

If not, you can add the following line in the dns configuration but you normally don't need it as a `.well-known` file is edited during the install to declare your server name and port to the federation.

```
_matrix._tcp.<server_name.tld> <ttl> IN SRV 10 0 <port> <domain-or-subdomain-of-synapse.tld>
```

for example

```
_matrix._tcp.example.com. 3600    IN      SRV     10 0 <synapse_port> synapse.example.com.
```

You need to replace `<synapse_port>` by the real port. This port can be obtained by the command: `yunohost app setting <synapse_instance_name> port_synapse_tls`

For more details, see : <https://github.com/element-hq/synapse/blob/master/docs/federate.md>

If it is not automatically done, you need to open this in your ISP box.

You also need a valid TLS certificate for the domain used by synapse. To do that you can refer to the documentation here : <https://yunohost.org/#/certificate_en>

<https://federationtester.matrix.org/> can be used to easily debug federation issues

## Turnserver

For Voip and video conferencing a turnserver is also installed (and configured). The turnserver listens on two UDP and TCP ports. You can get them with these commands:

```bash
yunohost app setting synapse port_turnserver_tls
yunohost app setting synapse port_turnserver_alt_tls
```

The turnserver will also choose a port dynamically when a new call starts. The range is between 49153 - 49193.

For some security reason the ports range (49153 - 49193) isn't automatically open by default. If you want to use the synapse server for voip or conferencing you will need to open this port range manually. To do this just run this command:

```bash
yunohost firewall allow Both 49153:49193
```

You might also need to open these ports (if it is not automatically done) on your ISP box.

To prevent the situation when the server is behind a NAT, the public IP is written in the turnserver config. By this the turnserver can send its real public IP to the client. For more information see [the coturn example config file](https://github.com/coturn/coturn/blob/master/examples/etc/turnserver.conf#L102-L120).So if your IP changes, you could run the script `/opt/yunohost/matrix-<synapse_instance_name>/Coturn_config_rotate.sh` to update your config.

If you have a dynamic IP address, you also might need to update this config automatically. To do that just edit a file named `/etc/cron.d/coturn_config_rotate` and add the following content (just adapt the `<synapse_instance_name>` which could be `synapse` or maybe `synapse__2`).

```
*/15 * * * * root bash /opt/yunohost/matrix-<synapse_instance_name>/Coturn_config_rotate.sh;
```

## OpenVPN

In case of you have an OpenVPN server you might want than `synapse-coturn` restart when the VPN restart. To do this create a file named `/usr/local/bin/openvpn_up_script.sh` with this content:

```bash
#!/bin/bash

(
    sleep 5
    sudo systemctl restart synapse-coturn.service
) &
exit 0
```

Add this line in you sudo config file `/etc/sudoers`

```
openvpn    ALL=(ALL) NOPASSWD: /bin/systemctl restart synapse-coturn.service
```

And add this line in your OpenVPN config file

```
ipchange /usr/local/bin/openvpn_up_script.sh
```

## Important Security Note

We do not recommend running Element from the same domain name as your Matrix
homeserver (synapse).  The reason is the risk of XSS (cross-site-scripting)
vulnerabilities that could occur if someone caused Element to load and render
malicious user generated content from a Matrix API which then had trusted
access to Element (or other apps) due to sharing the same domain.

We have put some coarse mitigations into place to try to protect against this
situation, but it's still not a good practice to do it in the first place. See
<https://github.com/vector-im/element-web/issues/1977> for more details.

## Limitations

Synapse uses a lot of ressource. So on slow architecture (like small ARM board), this app could take a lot of CPU and RAM.

This app doesn't provide any real good web interface. So it's recommended to use Element client to connect to this app. This app is available [here](https://github.com/YunoHost-Apps/element_ynh)

# Additional information

## Administration

**All documentation of this section is not warranted. A bad use of command could break the app and all the data. So use these commands at your own risk.**

Before any manipulation it's recommended to do a backup by this following command :

`sudo yunohost backup create --apps synapse`

### Set user as admin

Actually there are no functions in the client interface to set a user as admin. So it's possible to enable it manually in the database.

The following command will grant admin privilege to the specified user:

```bash
/opt/yunohost/matrix-<synapse_instance_name>/set_admin_user.sh '@user_to_be_admin:domain.tld'
```

### Administration API

There are an admiminstration application available if needed for example to use [Synapse Admin](https://github.com/YunoHost-Apps/synapse-admin_ynh).

Then, to log in the API with your credentials, you need to set your user as admin (cf. precedent section).

### Change url

Synapse give the possibility to change the domain of the instance. Note that this will only change the domain on which the synapse server will run. **This won't change the domain name of the account which is an other thing.**

The advantage of this is that you can put the app on a specific domain without impacting the domain name of the accounts. For instance you can have the synapse app on `matrix.yolo.net` and the user account will be something like that `@michu:yolo.net`. Note that it's the main difference between the domain of the app (which is `matrix.yolo.net`) and the "server name" which is `yolo.net`.

**Note that this change will have some important implications:**

- **This will break the connection from all previous connected clients. So all client connected before this change won't be able to communicate with the server until users will do a logout and login (which can also be problematic for e2e keys).** [There are a workaround which are described below](#avoid-the-need-to-reconnect-all-client-after-change-url-operation).
- In some case the client configuration will need to be updated. By example on element we can configure a default matrix server, this settings by example will need to be updated to the new domain to work correctly.
- In case of the "server name" domain are not on the same server than the synapse domain, you will need to update the `.well-known` or your DNS.

To do the change url of synapse you can do it by this following command or with the webadmin.

```bash
yunohost app change-url synapse
```

#### Avoid the need to reconnect all client after change-url operation

In case of you have changed the url of synapse and you don't wan't to reconnect all client there are this workaround which should solve the issue.

The idea is to setup again a minimal configuration on the previous domain so the client configurated with the previous domain will still work correctly.

##### Nginx config

Retrive the server port with this command:

```bash
yunohost app setting synapse port_synapse
```

Edit the file `/etc/nginx/conf.d/<previous-domain.tld>.d/synapse.conf` and add this text:

```
location /_matrix/ {
        proxy_pass http://localhost:<server_port_retrived_before>;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;

        client_max_body_size 200M;
}
```

Then reload nginx config:

```bash
systemctl reload nginx.service
```

##### Add permanent rule on SSOWAT

- Edit the file `/etc/ssowat/conf.json.persistent`
- Add `"<previous-domain.tld>/_matrix"` into the list in: `permissions` > `custom_skipped` > `uris`

Now the configured client before the change-url should work again.

### Backup

This app use now the core-only feature of the backup. To keep the integrity of the data and to have a better guarantee of the restoration is recommended to proceed like this:

- Stop synapse service with theses following command:

```bash
systemctl stop synapse.service
```

- Launch the backup of synapse with this following command:

```bash
yunohost backup create --app synapse
```

- Do a backup of your data with your specific strategy (could be with rsync, borg backup or just cp). The data is generally stored in `/home/yunohost.app/synapse`.
- Restart the synapse service with these command:

```bash
systemctl start synapse.service
```

### Remove

Due of the backup core only feature the data directory in `/home/yunohost.app/synapse` **is not removed**.

Use the `--purge` flag with the command, or remove it manually to purge app user data.

## Slow server

If your server is slow, you can do the following, according to [the official doc](https://matrix-org.github.io/synapse/latest/usage/administration/admin_faq.html#help-synapse-is-slow-and-eats-all-my-ramcpu):

- increase the `SYNAPSE_CACHE_FACTOR` value in your `/etc/default/matrix-__APP__`, `2` is a good value
  - note that the counterpart is more RAM usage
- if synapse is heavy on CPU, you can try to disable presence tracking in your config, using the config panel, under "User Experience" category
- note: this package already implemented the `libjemalloc` part, you con't need to touch that
