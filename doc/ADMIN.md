## Web client

The most well-known Matrix web client is Element, which is available in the YunoHost app catalog: <https://github.com/YunoHost-Apps/element_ynh>.

### Important Security Note

We do not recommend running Element from the same domain name as your Matrix homeserver (synapse).  The reason is the risk of XSS (cross-site-scripting) vulnerabilities that could occur if someone caused Element to load and render malicious user generated content from a Matrix API which then had trusted access to Element (or other apps) due to sharing the same domain.

We have put some coarse mitigations into place to try to protect against this situation, but it's still not a good practice to do it in the first place. See https://github.com/vector-im/element-web/issues/1977 for more details.

## Admin UI

You may be interested in the synapse-admin app,  which provides an administration interface for synapse:  <https://github.com/YunoHost-Apps/synapse-admin_ynh>.

Then, to log in the API with your admin credentials (cf next section)

### Set user as admin

Currently, the client interface doesn't allow to grant admin rights.
So you can follow this process to set the user as admin:
1. Login with any client as a standards user (like Element). This will create the user in synapse.
2. You have theses 2 solution:
    - On the Yunohost Webadmin, go on: Applications > Synapse > Main Settings > On the "Add admin user" section you can select the user to set as admin.
    - You can run this following script:
```bash
/opt/yunohost/matrix-__APP__/set_admin_user.sh '@<user_to_be_admin>:<domain.tld>'
```

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

For more details, see : https://github.com/element-hq/synapse/blob/master/docs/federate.md

If it is not automatically done, you need to open this in your ISP box.

You also need a valid TLS certificate for the domain used by synapse. To do that you can refer to the documentation here : https://yunohost.org/#/certificate_en

https://federationtester.matrix.org/ can be used to easily debug federation issues

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

If your server is behind a VPN, you may want `synapse-coturn` ti automatically restart when the VPN restarts. To do this, create a file named `/usr/local/bin/openvpn_up_script.sh` with this content:
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

## Backup

Before any major maintenance action, it is recommended to backup the app.

To ensure the integrity of the data, it is recommended to explictly stop the server during the backup:

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

## Changing the server URL

**All documentation of this section is not warranted. A bad use of command could break the app and all the data. So use these commands at your own risk.**

Synapse give the possibility to change the domain of the instance. Note that this will only change the domain on which the synapse server will run. **This won't change the domain name of the account which is an other thing.**

The advantage of this is that you can put the app on a specific domain without impacting the domain name of the accounts. For instance you can have the synapse app on `matrix.yolo.net` and the user account will be something like that `@michu:yolo.net`. Note that it's the main difference between the domain of the app (which is `matrix.yolo.net`) and the "server name" which is `yolo.net`.

**Note that this change will have some important implications:**
- **This will break the connection from all previous connected clients. So all client connected before this change won't be able to communicate with the server until users will do a logout and login (which can also be problematic for e2e keys).** [There are a workaround which are described below](#avoid-the-need-to-reconnect-all-client-after-change-url-operation).
- In some case the client configuration will need to be updated. By example on element we can configure a default matrix server, this settings by example will need to be updated to the new domain to work correctly.
- In case of the "server name" domain are not on the same server than the synapse domain, you will need to update the `.well-known` or your DNS.

To do the change url of synapse you can do it by this following command or with the webadmin.

```bash
sudo yunohost app change-url synapse
```

### Avoid the need to reconnect all client after change-url operation

If you did change the url of synapse and you don't wan't to reconnect all client, this workaround should solve the issue.

The idea is to setup again a minimal configuration on the previous domain so the client configurated with the previous domain will still work correctly.

#### Nginx config

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

#### Add permanent rule on SSOWAT

- Edit the file `/etc/ssowat/conf.json.persistent`
- Add `"<previous-domain.tld>/_matrix"` into the list in: `permissions` > `custom_skipped` > `uris`

Now the configured client before the change-url should work again.

## Removing the app

The YunoHost policy is to not remove the data when removing an app (stored in `/home/yunohost.app/synapse`). Use the `--purge` flag during the removal of the app to remove those, or just manually delete the folder after the app is deleted.
