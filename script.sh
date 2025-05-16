#!/bin/bash

# Color Code
YELLOW='\033[0;33m'
RED='\033[0;31m'
ORANGE='\033[38;5;214m'
GREEN='\033[0;32m'
NC='\033[0m'

host_memory_stat() {
    echo -e "${YELLOW}=============================================${NC}"
    echo -e "${YELLOW}Host Memory Stats${NC}"
    echo -e "${YELLOW}=============================================${NC}"

    read total used avail <<<$(free -h | awk '/Mem:/ {print $2, $3, $7}')

    total_num=$(echo $total | grep -oE '^[0-9.]+')
    used_num=$(echo $used | grep -oE '^[0-9.]+')
    usage_percent=$(awk "BEGIN {printf \"%.2f\", ($used_num/$total_num)*100}")

    echo "Memory Usage: $(check_memory_usage $usage_percent)"
    echo "Used/Total: $used/$total"
    echo "Available: $avail"
}

to_gb() {
    printf "%.2f" "$(echo "$1/1024/1024" | bc -l)"
}

to_vm_mem_usage_percent() {
    local alloc_gb=$1
    local rss_gb=$2

    if (($(echo "$alloc_gb > 0" | bc -l))); then
        usage_percent=$(echo "scale=4; $rss_gb / $alloc_gb * 100" | bc)
    else
        usage_percent=0.00
    fi

    formatted_percent=$(printf "%.2f" "$usage_percent")

    check_memory_usage $formatted_percent
}

# Check memory usage
check_memory_usage() {
    local memory_usage=$1
    if (($(echo "$memory_usage >= 90" | bc -l))); then
        echo -e "${RED}${memory_usage}%${NC}"
    elif (($(echo "$memory_usage >= 60" | bc -l))) && (($(echo "$memory_usage < 90" | bc -l))); then
        echo -e "${ORANGE}${memory_usage}%${NC}"
    else
        echo -e "${GREEN}${memory_usage}%${NC}"
    fi
}

check_usable() {
    local usable_gb=$1
    local alloc_gb=$2

    # 퍼센트 계산 (소수점 포함)
    local percent
    percent=$(echo "scale=2; $usable_gb / $alloc_gb * 100" | bc -l)

    # 색상 조건 분기 (기준은 %)
    if (($(echo "$percent <= 20" | bc -l))); then
        echo -e "${RED}$(printf '%.2f' "$usable_gb")Gi (${percent}%)${NC}"
    elif (($(echo "$percent <= 50" | bc -l))); then
        echo -e "${ORANGE}$(printf '%.2f' "$usable_gb")Gi (${percent}%)${NC}"
    else
        echo -e "$(printf '%.2f' "$usable_gb")Gi (${percent}%)"
    fi
}

vm_memory_stat() {
    echo -e "\n${YELLOW}=============================================${NC}"
    echo -e "${YELLOW}VM Memory Stats${NC}"
    echo -e "${YELLOW}=============================================${NC}"

    # Check if virsh is installed
    if ! command -v virsh &>/dev/null; then
        echo -e "${RED}[ERROR] virsh command not found. Please install libvirt-clients package${NC}"
        exit 1
    fi

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[NOTICE] You need to execute this script as root if you want to check VM memory stats${NC}"
        exit 1
    fi

    # 헤더와 데이터를 함께 버퍼링 후 column 처리
    {
        # 헤더
        printf "%-25s|%-25s|%-15s|%-20s|%-12s|%-12s\n" \
            "VM Name" "RSS/Alloc(%)" "Available" "Usable(%)" "Cache" "Unused"

        # 데이터
        for vm in $(virsh list --name); do
            stats=$(virsh domstats --balloon "$vm" | tr '\n' ' ')

            current=$(echo "$stats" | grep -o 'balloon.current=[0-9]*' | cut -d= -f2)
            rss=$(echo "$stats" | grep -o 'balloon.rss=[0-9]*' | cut -d= -f2)
            usable=$(echo "$stats" | grep -o 'balloon.usable=[0-9]*' | cut -d= -f2)
            unused=$(echo "$stats" | grep -o 'balloon.unused=[0-9]*' | cut -d= -f2)
            cache=$(echo "$stats" | grep -o 'balloon.disk_caches=[0-9]*' | cut -d= -f2)
            available=$(echo "$stats" | grep -o 'balloon.available=[0-9]*' | cut -d= -f2)

            current=${current:-0}
            rss=${rss:-0}
            usable=${usable:-0}
            unused=${unused:-0}
            cache=${cache:-0}

            rss_gb=$(to_gb $rss)
            current_gb=$(to_gb $current)
            percent=$(to_vm_mem_usage_percent $current_gb $rss_gb)

            usable_gb=$(to_gb $usable)
            colored_usable=$(check_usable $usable_gb $current_gb)

            unused_gb=$(to_gb $unused)

            printf "%-25s|%-25s|%-15s|%-20s|%-12s|%-12s\n" \
                "$vm" \
                "${rss_gb}/${current_gb}Gi ($percent)" \
                "$(to_gb $available)Gi" \
                "$colored_usable" \
                "$(to_gb $cache)Gi" \
                "${unused_gb}"
        done
    } | column -t -s "|"
}

host_memory_stat

vm_memory_stat
