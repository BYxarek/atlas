<?php
return [
    'data_dir' => __DIR__ . '/_data',
    'max_rooms' => 4,
    'poll_ms' => 1000,
    'lease_seconds' => 20,
    // CLI cron needs no key. For an HTTPS cron URL set your own random key (32+ characters).
    'cron_key' => '',
];
