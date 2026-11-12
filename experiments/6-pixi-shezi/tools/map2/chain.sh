cd /tmp/claude-0/-home-user-zxc/6f6fece3-c046-5882-9d45-337485949872/scratchpad/geo
until [ $(grep -l "l1 ok" b_l1_*.log 2>/dev/null | wc -l) -ge 4 ]; do sleep 10; done
for r in "0 3" "3 6" "6 9" "9 12"; do set -- $r; python3 bake_map.py l2 $1 $2 > b_l2_$1.log 2>&1 & done
python3 make_simdata.py > simdata.log 2>&1
wait
echo ALLDONE > chain.done
