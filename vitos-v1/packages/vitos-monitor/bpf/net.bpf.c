// SPDX-License-Identifier: GPL-2.0
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

char LICENSE[] SEC("license") = "GPL";

struct flow_event {
    __u64 ts;
    __u32 saddr;
    __u32 daddr;
    __u16 sport;
    __u16 dport;
    __u8  proto;
    __u32 bytes;
};

struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 1 << 20);
} flows SEC(".maps");

SEC("tc")
int tc_egress(struct __sk_buff *skb)
{
    void *data = (void *)(long)skb->data;
    void *end  = (void *)(long)skb->data_end;
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > end) return 0;
    if (eth->h_proto != bpf_htons(0x0800)) return 0;
    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > end) return 0;

    struct flow_event *e = bpf_ringbuf_reserve(&flows, sizeof(*e), 0);
    if (!e) return 0;
    e->ts    = bpf_ktime_get_ns();
    e->saddr = ip->saddr;
    e->daddr = ip->daddr;
    e->proto = ip->protocol;
    e->sport = 0;
    e->dport = 0;
    e->bytes = skb->len;
    bpf_ringbuf_submit(e, 0);
    return 0;
}
