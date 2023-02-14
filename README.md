# Porkbun DDNS

The `porkbun_ddns.sh` is a command-line tool for Porkbun DDNS (Dynamic Domain Name Server). It is written in the shell and has very few dependencies.

### Features:
1. Few dependencies, only need curl and dig installed.
2. Supports both IPv4 and IPv6.
3. Unlike other scripts, this script can still obtain the real IP in the proxy environment.
4. Can theoretically run on most computers or routers.

### Usage:
1. Download the shell script then upload it to a folder on your computer or router, e.g. `/usr/bin`.
2. Confirm that the curl and dig commands are available on your machine. Actually the script will also help to check.
3. Give the shell script executable permissions.
```bash
chmod +x /usr/bin/porkbun_ddns.sh
```
4. Execute the following command to get usage help information.
```bash
porkbun_ddns.sh --help

Porkbun DDNS CLI v1.0.0 (2022.05.20)
Usage: porkbun-ddns.sh <command> ... [parameters ...]
Commands:
  --help                        Show this help message
  --version                     Show version info
  --api-key, -ak <apikey>       Specify Namesilo API Key
  --secret-key, -sk <secretkey> Specify Namesilo Secret Key
  --host, -h <host>             Add a hostname

Example:
  porkbun-ddns.sh \
    -ak pk1_jeldvj74ql06qq81rfx7jqsaubno867q4zp3b2fi06pw2bns81innur6p0oq3n7s \
    -sk sk1_kfkcxsgne1i8qm4mr8va8t9e8f5ezpw8fsin35uh8jjqwhgsfb7571y2wq3shdgx \
    -h domain1.tld \
    -h subdomain.domain1.tld \
    -h subdomain.domain2.tld

Exit codes:
  0 Successfully updating for all host(s)
  9 Arguments error

Tips:
  Strongly recommand to refetch records or clear caches in file,
  if your DNS records have been updated by other ways.
```
5. Set parameters according to your actual situation, then run the shell script and view the results.
6. After confirming that it is correct, you can also add it to the crontab for automatic execution.
```bash
# e.g.
# Run every five minutes
*/5 * * * * porkbun-ddns.sh -ak pk1_jeldvj74ql06qq81rfx7jqsaubno867q4zp3b2fi06pw2bns81innur6p0oq3n7s -sk sk1_kfkcxsgne1i8qm4mr8va8t9e8f5ezpw8fsin35uh8jjqwhgsfb7571y2wq3shdgx -h domain1.tld -h subdomain.domain1.tld -h subdomain.domain2.tld
```

### Changelog:
1. 2022/5/20 - Release v1.0.0 version.

### Thanks:
1. [Mr-Jos/namesilo_ddns_cli](https://github.com/Mr-Jos/namesilo_ddns_cli)
