#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;
use above 'Workflow';

my $dir = -d 't/xml.d' ? 't/xml.d' : 'xml.d';

require_ok('Workflow::Model');
can_ok('Workflow::Model',qw/create validate is_valid execute/);

my $w = Workflow::Model->create_from_xml($dir . '/13_parallel_complex.xml');
ok($w,'create workflow');
isa_ok($w,'Workflow::Model');

ok(do {
    $w->validate;
    $w->is_valid;
},'validate');

my $data = $w->execute(
    input => {
        'test input' => [
            qw/ab cd ef gh jk/
        ]
    }
);

$w->wait;

my $output = $data->output;

$data->treeview_debug;

is_deeply(
    $output,
    {
        'test output' => [qw/ab cd ef gh jk ab cd ef gh jk/],
        'result' => 1 
    },
    'check output'
);
