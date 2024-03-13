If your server name is identical to the domain on which synapse is installed, and the default port 8448 is used, your server is normally already accessible by the federation.

If not, you may need to put the following line in the dns configuration:

```text
_matrix._tcp.__DOMAIN__. 3600    IN      SRV     10 0 __PORT_SYNAPSE_TLS__ __DOMAIN__.
```

For more details, see : <https://github.com/element-hq/synapse#setting-up-federation>

You also need to open the TCP port __PORT_SYNAPSE_TLS__ on your ISP box if it's not automatically done.

Your synapse server also implements a turnserver (for VoIP), to have this fully functional please read the 'Turnserver' section in the README available here: <https://github.com/YunoHost-Apps/synapse_ynh> .

If you're facing an issue or want to improve this app, please open a new issue in this project: <https://github.com/YunoHost-Apps/synapse_ynh>

You also need a valid TLS certificate for the domain used by synapse. To do that you can refer to the documentation here : <https://yunohost.org/#/certificate_en>
