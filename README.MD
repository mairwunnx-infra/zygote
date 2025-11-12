# Zygote of the Infrastructure

[![AI Capable](https://img.shields.io/badge/AI-Capable-brightgreen?style=flat&logo=openai&logoColor=white)](https://github.com/mairwunnx-infra/ingress)
[![Portainer](https://img.shields.io/badge/Portainer-13BEF9?style=flat&logo=portainer&logoColor=white)](https://www.portainer.io/)

Зигота инфраструктуры, которую я использую для своего сервера.

Минимальный минимум для старта деплоймента на мой взгляд, в `docker-compose.yaml` имеется лишь один сервис - **Portainer**.

С помощью него уже в дальнейшем можно будет добавлять новые сервисы и конфигурировать их, в общем оркестрировать.

Так же имеется стартовый сценарий `init.sh`, который устанавливает **Docker**, настраивает **IPv6**, устанавливает **iptables** и **ip6tables**, создает внешнюю сеть `infra`.

Все что остается выполнить после этого, это запустить сам сервис **Portainer**:

```bash
docker compose up -d
```

Остальные деплойменты в отдельных репозиториях этой же организации.

> Примечание: если случаем, возьмете этот репозиторий как за истину решений, сто раз убедитесь, что сеть настраивается под ваши нужды или вообще уберите настройку сети.

### Связные ссылки:

- [Infra Xi Manager](https://github.com/mairwunnx-infra/ximanager) - Portainer стек для проекта Xi Manager.
- [Infra Dickobrazz](https://github.com/mairwunnx-infra/dickobrazz) - Portainer стек для проекта Dickobrazz.
- [Infra VS Code](https://github.com/mairwunnx-infra/vscode) - Portainer стек для VS Code.
- [Infra GitLab](https://github.com/mairwunnx-infra/gitlab) - Portainer стек для GitLab.
- [Infra Jenkins](https://github.com/mairwunnx-infra/jenkins) - Portainer стек для Jenkins.
- [Infra Ingress](https://github.com/mairwunnx-infra/ingress) - Portainer стек для reverse proxy.

---

<img src="./media.png" alt="Русская сила" width="500">

🇷🇺 **Сделано в России с любовью.** ❤️

> 🫡 Made by Pavel Erokhin (Павел Ерохин), aka mairwunnx.