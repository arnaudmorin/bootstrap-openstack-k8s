# How to order an IP failover block on OVHcloud from APIv6

First, build a venv:
```bash
python3 -m venv order-venv
source order-venv/bin/activate
```

Then install ovh client:
```bash
pip3 install ovh
```

Then order the IP failover block
```bash
cp ovh.conf.sample ovh.conf
python3 order_ip_block.py
```

You will be guided through creating an Application.
At the end, the tool will print an order that you'll have to pay in order to receive your block.

