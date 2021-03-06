#!/bin/bash
#
# Bug SW #1341628: Bad rules added when offloading rules to HW
#

NIC=${1:-ens5f0}

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_mlxdump

enable_switchdev_if_no_rep $REP
require_interfaces REP
unbind_vfs
set_eswitch_inline_mode_transport
bind_vfs

reset_tc_nic $NIC
reset_tc_nic $REP

rm -fr /tmp/fsdump_before_add /tmp/fsdump_after_add

mlxdump -d $PCI fsdump --type FT --no_zero > /tmp/fsdump_before_add || err "mlxdump failed"

title "Add tc rules"

tc filter add dev $NIC protocol ip parent ffff: prio 1 \
        flower \
                skip_sw \
                dst_mac e4:11:22:11:4a:51 \
                src_mac e4:11:22:11:4a:50 \
                src_ip 1.1.1.1 \
                dst_ip 2.2.2.2 \
            action mirred egress redirect dev $REP || err "Failed adding nic->rep rule"

tc filter add dev $REP protocol ip parent ffff: prio 2 \
        flower \
                skip_sw \
                dst_mac e4:11:22:11:4a:50 \
                src_mac e4:11:22:11:4a:51 \
                src_ip 2.2.2.2 \
                dst_ip 1.1.1.1 \
            action mirred egress redirect dev $NIC || err "Failed adding rep->nic rule"

fail_if_err

title "Check diff"

mlxdump -d $PCI fsdump --type FT --no_zero > /tmp/fsdump_after_add || err "mlxdump failed"

DIF=`diff -u /tmp/fsdump_before_add /tmp/fsdump_after_add`

if [ -z "$DIF" ]; then
    err "Empty diff /tmp/fsdump_before_add /tmp/fsdump_after_add"
fi

count=`diff -u /tmp/fsdump_before_add /tmp/fsdump_after_add | grep "+- FTE" | wc -l`

if [[ $count -eq 2 ]]; then
    success
else
    err "Expected 2 new FTEs in HW but got $count"
fi

reset_tc_nic $NIC
reset_tc_nic $REP
test_done
