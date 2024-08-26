<!--
注意：此 README 由 <https://github.com/YunoHost/apps/tree/master/tools/readme_generator> 自动生成
请勿手动编辑。
-->

# YunoHost 上的 Synapse

[![集成程度](https://dash.yunohost.org/integration/synapse.svg)](https://ci-apps.yunohost.org/ci/apps/synapse/) ![工作状态](https://ci-apps.yunohost.org/ci/badges/synapse.status.svg) ![维护状态](https://ci-apps.yunohost.org/ci/badges/synapse.maintain.svg)

[![使用 YunoHost 安装 Synapse](https://install-app.yunohost.org/install-with-yunohost.svg)](https://install-app.yunohost.org/?app=synapse)

*[阅读此 README 的其它语言版本。](./ALL_README.md)*

> *通过此软件包，您可以在 YunoHost 服务器上快速、简单地安装 Synapse。*  
> *如果您还没有 YunoHost，请参阅[指南](https://yunohost.org/install)了解如何安装它。*

## 概况

Instant messaging server matrix network.

Yunohost chatroom with matrix : [https://matrix.to/#/#yunohost:matrix.org](https://matrix.to/#/#yunohost:matrix.org)


**分发版本：** 1.100.0~ynh1
## 免责声明 / 重要信息

## Configuration

### Install for ARM arch (or slow arch)

For all slow or arm architecture it's recommended to build the dh file before the install to have a quicker install.
You could build it by this cmd : `openssl dhparam -out /etc/ssl/private/dh2048.pem 2048 > /dev/null`
After that you can install it without problem.

The package uses a prebuilt python virtual environnement. The binary are taken from this repository: https://github.com/Josue-T/synapse_python_build
The script to build the binary is also available.

### Web client

If you want a web client you can also install Element with this package: https://github.com/YunoHost-Apps/element_ynh .

### Access by federation

If your server name is identical to the domain on which synapse is installed, and the default port 8448 is used, your server is normally already accessible by the federation.

If not, you can add the following line in the dns configuration but you normally don't need it as a .well-known file is edited during the install to declare your server name and port to the federation.

```
_matrix._tcp.<server_name.tld> <ttl> IN SRV 10 0 <port> <domain-or-subdomain-of-synapse.tld>
```
for example
```
_matrix._tcp.example.com. 3600    IN      SRV     10 0 SYNAPSE_PORT synapse.example.com.
```
You need to replace SYNAPSE_PORT by the real port. This port can be obtained by the command: `yunohost app setting SYNAPSE_INSTANCE_NAME synapse_tls_port`

For more details, see : https://github.com/matrix-org/synapse/blob/master/docs/federate.md

If it is not automatically done, you need to open this in your ISP box.

You also need a valid TLS certificate for the domain used by synapse. To do that you can refer to the documentation here : https://yunohost.org/#/certificate_en

https://federationtester.matrix.org/ can be used to easily debug federation issues

### Turnserver

For Voip and video conferencing a turnserver is also installed (and configured). The turnserver listens on two UDP and TCP ports. You can get them with these commands:
```
yunohost app setting synapse turnserver_tls_port
yunohost app setting synapse turnserver_alt_tls_port

```
The turnserver will also choose a port dynamically when a new call starts. The range is between 49153 - 49193.

For some security reason the ports range (49153 - 49193) isn't automatically open by default. If you want to use the synapse server for voip or conferencing you will need to open this port range manually. To do this just run this command:

```
yunohost firewall allow Both 49153:49193
```

You might also need to open these ports (if it is not automatically done) on your ISP box.

To prevent the situation when the server is behind a NAT, the public IP is written in the turnserver config. By this the turnserver can send its real public IP to the client. For more information see [the coturn example config file](https://github.com/coturn/coturn/blob/master/examples/etc/turnserver.conf#L102-L120).So if your IP changes, you could run the script `/opt/yunohost/__SYNAPSE_INSTANCE_NAME__/Coturn_config_rotate.sh` to update your config.

If you have a dynamic IP address, you also might need to update this config automatically. To do that just edit a file named `/etc/cron.d/coturn_config_rotate` and add the following content (just adapt the __SYNAPSE_INSTANCE_NAME__ which could be `synapse` or maybe `synapse__2`).

```
*/15 * * * * root bash /opt/yunohost/__SYNAPSE_INSTANCE_NAME__/Coturn_config_rotate.sh;
```

#### OpenVPN

In case of you have an OpenVPN server you might want than `coturn-synapse` restart when the VPN restart. To do this create a file named `/usr/local/bin/openvpn_up_script.sh` with this content:
```
#!/bin/bash

(
    sleep 5
    sudo systemctl restart coturn-synapse.service
) &
exit 0
```

Add this line in you sudo config file `/etc/sudoers`
```
openvpn    ALL=(ALL) NOPASSWD: /bin/systemctl restart coturn-synapse.service
```

And add this line in your OpenVPN config file
```
ipchange /usr/local/bin/openvpn_up_script.sh
```

### Important Security Note

We do not recommend running Element from the same domain name as your Matrix
homeserver (synapse).  The reason is the risk of XSS (cross-site-scripting)
vulnerabilities that could occur if someone caused Element to load and render
malicious user generated content from a Matrix API which then had trusted
access to Element (or other apps) due to sharing the same domain.

We have put some coarse mitigations into place to try to protect against this
situation, but it's still not a good practice to do it in the first place. See
https://github.com/vector-im/element-web/issues/1977 for more details.

## YunoHost specific features

## Limitations

Synapse uses a lot of ressource. So on slow architecture (like small ARM board), this app could take a lot of CPU and RAM.

This app doesn't provide any real good web interface. So it's recommended to use Element client to connect to this app. This app is available [here](https://github.com/YunoHost-Apps/element_ynh)

## Additional information

## Administration

**All documentation of this section is not warranted. A bad use of command could break the app and all the data. So use these commands at your own risk.**

Before any manipulation it's recommended to do a backup by this following command :

`sudo yunohost backup create --apps synapse`

### Set user as admin

Actually there are no functions in the client interface to set a user as admin. So it's possible to enable it manually in the database.

The following command will grant admin privilege to the specified user:
```
su --command="psql matrix_synapse" postgres <<< "UPDATE users SET admin = 1 WHERE name = '@user_to_be_admin:domain.tld'"
```

### Administration API

Synapse's administration API endpoints are under `/_synapse` path and protected with the `admin_api` permission.
By default, no one has access to this path.

If you wish to access it, for example to use [Synapse Admin](https://github.com/YunoHost-Apps/synapse-admin_ynh),
you need to give this permission to visitors.

Then, to log in the API with your credentials, you need to set your user as admin (cf. precedent section).

### Upgrade

By default a backup is made before the upgrade. If for some reason you want to upgrade without backup:
- Call the command with the `-b` flag: `yunohost app upgrade synapse -b`
- Disable the setting `Backup before upgrade` in the Config Panel. Or with command line:

`yunohost app setting synapse backup_before_upgrade -v 0`

After this settings will be applied for **all** next upgrade.

From command line:

`yunohost app upgrade synapse`

### Backup

This app use now the core-only feature of the backup. To keep the integrity of the data and to have a better guarantee of the restoration is recommended to proceed like this:

- Stop synapse service with theses following command:

`systemctl stop synapse.service`

- Launch the backup of synapse with this following command:

`yunohost backup create --app synapse`

- Do a backup of your data with your specific strategy (could be with rsync, borg backup or just cp). The data is generally stored in `/home/yunohost.app/matrix-synapse`.
- Restart the synapse service with these command:

`systemctl start synapse.service`

### Remove

Due of the backup core only feature the data directory in `/home/yunohost.app/matrix-synapse` **is not removed**.

Use the `--purge` flag with the command, or remove it manually to purge app user data.

### Multi instance support

To give a possibility to have multiple domains you can use multiple instances of synapse. In this case all instances will run on different ports so it's really important to put a SRV record in your domain. You can get the port that you need to put in your SRV record with this following command:
```
yunohost app setting synapse__<instancenumber> synapse_tls_port
```

Before installing a second instance of the app it's really recommended to update all existing instances.

## 文档与资源

- 官方应用网站： <https://matrix.org/>
- 上游应用代码库： <https://github.com/matrix-org/synapse>
- YunoHost 商店： <https://apps.yunohost.org/app/synapse>
- 报告 bug： <https://github.com/YunoHost-Apps/synapse_ynh/issues>

## 开发者信息

请向 [`testing` 分支](https://github.com/YunoHost-Apps/synapse_ynh/tree/testing) 发送拉取请求。

如要尝试 `testing` 分支，请这样操作：

```bash
sudo yunohost app install https://github.com/YunoHost-Apps/synapse_ynh/tree/testing --debug
或
sudo yunohost app upgrade synapse -u https://github.com/YunoHost-Apps/synapse_ynh/tree/testing --debug
```

**有关应用打包的更多信息：** <https://yunohost.org/packaging_apps>
