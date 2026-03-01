#!/usr/bin/env python3
import requests
import ipaddress
import sys

API_URL = "http://api.uzuk.pro/check"

def check(query: str) -> None:
    try:
        r = requests.get(API_URL, params={"query": query}, timeout=10)
        r.raise_for_status()
        data = r.json()

        whitelisted = data.get("whitelisted")
        status = "✅ В белом списке (БС)" if whitelisted else "❌ НЕ в белом списке"

        print(f"\n{'─'*40}")
        print(f"  Запрос:   {data.get('query')}")
        print(f"  IP:       {data.get('ip')}")
        print(f"  Статус:   {status}")
        print(f"  ASN:      {data.get('asn')}")
        print(f"  Страна:   {data.get('country')}")
        print(f"{'─'*40}")
    except requests.exceptions.RequestException as e:
        print(f"  [Ошибка запроса] {query}: {e}")
    except Exception as e:
        print(f"  [Ошибка] {query}: {e}")


def expand_cidr(cidr: str):
    """Возвращает список IP из диапазона CIDR (максимум 256 адресов)."""
    try:
        net = ipaddress.ip_network(cidr, strict=False)
        hosts = list(net.hosts()) or [net.network_address]
        if len(hosts) > 256:
            print(f"  [!] Диапазон слишком большой ({len(hosts)} адресов), проверяю первые 256.")
            hosts = hosts[:256]
        return [str(h) for h in hosts]
    except ValueError:
        return None


def process_input(user_input: str):
    user_input = user_input.strip()
    if not user_input:
        return

    # Попытка распарсить как CIDR
    if "/" in user_input:
        ips = expand_cidr(user_input)
        if ips:
            print(f"\n[*] Проверяю диапазон {user_input} ({len(ips)} адресов)...")
            for ip in ips:
                check(ip)
            return
        else:
            print(f"  [!] Не удалось распарсить диапазон: {user_input}")
            return

    # Диапазон вида 192.168.1.1-192.168.1.10
    if "-" in user_input and not user_input.startswith("-"):
        parts = user_input.split("-")
        if len(parts) == 2:
            try:
                start = ipaddress.ip_address(parts[0].strip())
                end = ipaddress.ip_address(parts[1].strip())
                ips = []
                current = start
                while current <= end:
                    ips.append(str(current))
                    current += 1
                    if len(ips) > 256:
                        print(f"  [!] Диапазон слишком большой, проверяю первые 256.")
                        break
                print(f"\n[*] Проверяю диапазон {user_input} ({len(ips)} адресов)...")
                for ip in ips:
                    check(ip)
                return
            except ValueError:
                pass  # Не диапазон IP, возможно домен

    # Одиночный IP или домен
    check(user_input)


def main():
    print("╔══════════════════════════════════════╗")
    print("║      🔍 IP / Domain Checker          ║")
    print("║  Введите IP, диапазон или домен      ║")
    print("║  Для выхода: exit / quit / Ctrl+C    ║")
    print("╚══════════════════════════════════════╝")

    while True:
        try:
            user_input = input("\n> ").strip()
            if user_input.lower() in ("exit", "quit", "q"):
                print("Пока!")
                break
            process_input(user_input)
        except (KeyboardInterrupt, EOFError):
            print("\nПока!")
            break


if __name__ == "__main__":
    main()
