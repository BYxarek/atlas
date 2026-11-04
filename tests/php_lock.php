<?php
require __DIR__.'/../hosting/service.php';
for($i=0;$i<10;$i++)atlas_transaction(['data_dir'=>$argv[1]],function(&$state){$state['test_counter']=($state['test_counter']??0)+1;return [];});
