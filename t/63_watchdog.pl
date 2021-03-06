#!/usr/bin/env perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT}=1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS}=1;
}

use strict;
use warnings;
use Test::More;

plan tests => 2;

use above 'Workflow';
use Workflow::Simple;

my $op = Workflow::Operation->create(
    name => 'watchdog',
    operation_type => Workflow::OperationType::Command->get('Workflow::Test::Command::Watchdog')
);

my $output = run_workflow_lsf(
    $op,
    seconds => 120 
);

print Data::Dumper->new([$output,\@Workflow::Simple::ERROR])->Dump;


