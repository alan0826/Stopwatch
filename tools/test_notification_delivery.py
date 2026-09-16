#!/usr/bin/env python3
"""Run the production notification-retention policy's boundary regressions."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Stopwatch/Support/NotificationIdentifier.swift').read_text()
policy = source.split('struct NotificationSchedulingResult')[0]
policy = policy.replace('import UserNotifications', 'import Foundation')
tests = r'''
let now = Date(timeIntervalSince1970: 2000000000)
let prefix = NotificationID.reminderPrefix(for: UUID())
for delay in [0, 1, 10, 30, 120] {
    assert(NotificationID.isAwaitingDelivery(prefix + String(2000000000 - delay), at: now))
}
for delay in [-1, -60, 121, 3600] {
    assert(!NotificationID.isAwaitingDelivery(prefix + String(2000000000 - delay), at: now))
}
assert(!NotificationID.isAwaitingDelivery("unrelated-2000000000", at: now))
assert(!NotificationID.isAwaitingDelivery("reminder-invalid", at: now))
print("PASS: 11 notification delivery boundary cases")
'''
with tempfile.TemporaryDirectory(prefix='stopwatch-delivery-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text(policy + tests)
    subprocess.run(['swift', '-module-cache-path', str(Path(directory) / 'cache'), str(path)], check=True)
