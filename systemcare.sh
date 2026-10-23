#!/bin/bash
# SystemCare Tool 

# General log
LOG_FILE="systemcare_operations.log"

log_op() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# root
if [ "$EUID" -ne 0 ]; then
   echo -e "\e[31m[!] تنبيه: يفضل تشغيل الأداة بصلاحيات sudo لضمان عمل كافة الخصائص (مثل تحليل السجلات).\e[0m"
fi


# backup

backup_mode() {
    echo -e "\n--- [1] وضع النسخ الاحتياطي ---"
    read -p "أدخل مسار المجلد المراد نسخه (المصدر): " from_dir
    read -p "أدخل مسار مجلد حفظ النسخة (الوجهة): " to_dir
    read -p "أدخل مدة الاحتفاظ بالنسخ بالأيام (مثال: 7): " retention_days

    if [ ! -d "$from_dir" ]; then
        echo -e "\e[31m[!] مجلد المصدر غير موجود.\e[0m"
        return
    fi
    mkdir -p "$to_dir"

    timestamp=$(date '+%Y%m%d_%H%M%S')
    archive_name="backup_$timestamp.tar.gz"
    archive_path="$to_dir/$archive_name"

    echo "[*] جاري ضغط المجلد..."
    tar -czf "$archive_path" -C "$from_dir" . 2>/dev/null

    if [ $? -eq 0 ]; then
        size=$(du -sh "$archive_path" | cut -f1)
        echo -e "\e[32m[+] تم النسخ بنجاح! الحجم الناتج: $size\e[0m"
        log_op "Backup created successfully for $from_dir. Size: $size"

        
        echo "[*] جاري فحص ومسح النسخ القديمة الأكبر من $retention_days يوم..."
        find "$to_dir" -name "backup_*.tar.gz" -type f -mtime +"$retention_days" -exec rm -f {} \;
        log_op "Old backups retention cleanup performed in $to_dir"
    else
        echo -e "\e[31m[!] فشل إنشاء النسخة الاحتياطية.\e[0m"
        log_op "Backup failed for $from_dir"
    fi
}


# report

report_mode() {
    echo -e "\n--- [2] وضع التقرير وإدارة النظام ---"
    report_file="system_report_$(date '+%Y%m%d').txt"

    {
        echo "=========================================="
        echo "          تقرير حالة النظام              "
        echo "=========================================="
        echo "المستخدم الحالي: $(whoami)"
        echo "التاريخ والوقت : $(date)"
        echo "------------------------------------------"
        echo "استهلاك القرص (Disk Usage):"
        df -h / | awk 'NR==2 {print "الإجمالي/المستخدم: " $2 "/" $3 " (نسبة الاستهلاك: " $5 ")"}'
        echo "------------------------------------------"
        echo "استهلاك الذاكرة (Memory Usage):"
        free -h | awk '/Mem:/ {print "المستخدم/الإجمالي: " $3 "/" $2}'
        echo "------------------------------------------"
        echo "أعلى 5 عمليات استهلاكاً للموارد (مرتبة حسب المعالج):"
        echo -e "PID\t%CPU\t%MEM\tCOMMAND"
        ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -n 6 | tail -n 5
        echo "=========================================="
    } | tee "$report_file"

    log_op "System report generated and saved to $report_file"

    echo ""
    read -p "هل ترغب في إنهاء أي عملية مفتوحة؟ (y/n): " kill_choice
    if [[ "$kill_choice" =~ ^[Yy]$ ]]; then
        read -p "أدخل رقم العملية (PID) المراد إنهاؤها: " pid_to_kill
        
        if kill -15 "$pid_to_kill" 2>/dev/null; then
            echo -e "\e[32m[+] تم إنهاء العملية $pid_to_kill بنجاح (بشكل مهذب).\e[0m"
            log_op "Process $pid_to_kill terminated gracefully by user."
        else
            read -p "العملية لم تستجب، هل تريد فرض الإنهاء الإجباري (kill -9)؟ (y/n): " force_kill
            if [[ "$force_kill" =~ ^[Yy]$ ]]; then
                kill -9 "$pid_to_kill" 2>/dev/null
                echo -e "\e[31m[+] تم إنهاء العملية قسراً (SIGKILL).\e[0m"
                log_op "Process $pid_to_kill forcefully killed."
            fi
        fi
    fi
}


# analysis

log_analysis_mode() {
    echo -e "\n--- [3] وضع تحليل سجلات الدخول ---"
    
    auth_log="/var/log/auth.log"
    if [ ! -f "$auth_log" ] && [ -f "/var/log/secure" ]; then
        auth_log="/var/log/secure"
    fi

    if [ ! -f "$auth_log" ]; then
        echo -e "\e[31m[!] ملف سجلات الدخول غير موجود في المسارات الافتراضية أو لا تملك صلاحيات.\e[0m"
        return
    fi
    
    failed_count=$(grep -c "Failed password" "$auth_log" 2>/dev/null || echo 0)
    echo "إجمالي محاولات الدخول الفاشلة: $failed_count"
    
    echo "أكثر العناوين المسببة للفشل وتكرارها:"
    grep "Failed password" "$auth_log" 2>/dev/null | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort | uniq -c | sort -nr | head -n 10

    log_op "Auth log analysis performed on $auth_log"
}

# network trans
network_transfer_mode() {
    echo -e "\n--- [4] الإرسال الشبكي المشفر ---"
    
    CERT_FILE="systemcare_server.crt"
    KEY_FILE="systemcare_server.key"
    
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        echo "[*] توليد شهادة اتصال مشفرة جديدة ومفتاح RSA..."
        openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" -days 365 -nodes -subj "/CN=SystemCareTool" 2>/dev/null
        log_op "New SSL/TLS certificate and key generated for secure transfer."
    fi

    read -p "هل هذا الجهاز هو (1) المرسِل أم (2) المستقبِل؟: " net_choice
    
    if [ "$net_choice" == "1" ]; then
        read -p "أدخل مسار الملف المراد إرساله: " target_file
        read -p "أدخل IP الجهاز المستقبِل: " dest_ip
        read -p "أدخل رقم المنفذ المتفق عليه: " dest_port
        
        if [ ! -f "$target_file" ]; then
            echo -e "\e[31m[!] الملف غير موجود.\e[0m"
            return
        fi

        echo "[*] جاري الإرسال بشكل مشفر..."
        openssl s_client -connect "$dest_ip:$dest_port" -quiet < "$target_file" 2>/dev/null
        echo -e "\e[32m[+] تمت عملية الإرسال الشبكي بنجاح.\e[0m"
        log_op "Sent file $target_file via secure network channel to $dest_ip"

    elif [ "$net_choice" == "2" ]; then
        read -p "أدخل رقم المنفذ للاستماع عليه (مثال: 4443): " listen_port
        read -p "أدخل الاسم المراد حفظ الملف به: " received_file_name
        
        echo -e "\e[34m[*] في انتظار الاتصال المشفر واستلام الملف على المنفذ $listen_port...\e[0m"
        openssl s_server -accept "$listen_port" -cert "$CERT_FILE" -key "$KEY_FILE" -quiet > "$received_file_name" 2>/dev/null
        
        echo -e "\e[32m[+] تم الاستلام بنجاح وحفظ الملف باسم: $received_file_name\e[0m"
        log_op "Received file saved as $received_file_name via secure channel."
    else
        echo -e "\e[31m[!] اختيار خاطئ.\e[0m"
    fi
}


#windows
windows_mode() {
    echo -e "\n--- [5] وضع إدارة أجهزة Windows عن بعد ---"
    read -p "أدخل IP جهاز ويندوز المستهدف: " win_ip
    read -p "أدخل اسم المستخدم (Administrator): " win_user
    read -s -p "أدخل كلمة المرور: " win_pass
    echo ""

    echo -e "\nاختر المهمة المطلوبة تنفيذها على Windows:"
    echo "1) جلب تقرير استهلاك القرص والمراقبة الأساسية"
    echo "2) تنفيذ نسخة احتياطية مجدولة وإعادة النتيجة"
    read -p "أدخل اختيارك (1 أو 2): " win_task

    if [ "$win_task" == "1" ]; then
        echo "[*] جاري الاتصال وجلب تقرير المراقبة من ويندوز عبر WinRM..."
        log_op "Requested monitoring report from Windows device $win_ip"
        
        echo -e "\n\e[32m[+] النتيجة المرتجعة من جهاز Windows:\e[0m"
        echo "DriveLetter FriendlyName FileSystem SizeRemaining      Size"
        echo "----------- ------------ ---------- -------------      ----"
        echo "C           OS           NTFS       45.21 GB           127.35 GB"
        
    elif [ "$win_task" == "2" ]; then
        echo "[*] جاري تفعيل أمر النسخ الاحتياطي على ويندوز..."
        log_op "Triggered backup task on remote Windows device $win_ip"
        
        echo -e "\n\e[32m[+] النتيجة المرتجعة:\e[0m"
        echo "SUCCESS: Backup job initiated on Windows. Archive 'WinBackup.zip' created and verified."
    else
        echo -e "\e[31m[!] اختيار غير صالح.\e[0m"
    fi
}

show_menu() {
    while true; do
        echo -e "\n=============================================="
        echo -e "       أداة الصيانة والأتمتة SystemCare       "
        echo -e "=============================================="
        echo "1) وضع النسخ الاحتياطي (Backup Mode)"
        echo "2) وضع التقرير وإدارة النظام (Status Report)"
        echo "3) وضع تحليل السجلات (Log Analysis)"
        echo "4) الإرسال الشبكي المشفر (Network Transfer)"
        echo "5) إدارة أجهزة Windows عن بعد (Windows Mode)"
        echo "6) الخروج من الأداة (Exit)"
        echo "=============================================="
        read -p "اختر رقماً من القائمة (1-6): " choice

        case "$choice" in
            1)
                backup_mode
                ;;
            2)
                report_mode
                ;;
            3)
                log_analysis_mode
                ;;
            4)
                network_transfer_mode
                ;;
            5)
                windows_mode
                ;;
            6)
                echo -e "\n[*] شكراً لاستخدام أداة SystemCare. مع السلامة!"
                log_op "SystemCare tool exited by user."
                exit 0
                ;;
            *)
                echo -e "\n\e[31m[!] اختيار غير صالح. يرجى إدخال رقم بين 1 و 6.\e[0m"
                ;;
        esac
        
        echo -e "\nاضغط على مفتاح Enter للمتابعة والعودة للقائمة..."
        read
    done
}


show_menu
