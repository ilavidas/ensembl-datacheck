=head1 NAME

  LRG - User-defined integrity on mapping between the LRG coordinate system and its features (type 2 in the healthcheck system)

=head1 SYNOPSIS

  $ perl LRG.pl 'homo sapiens'

=head1 DESCRIPTION

  ARG[species]    : String - name of the species to check on.

  Database type   : Core

First checks if LRG coordinate system is present in the database for the given species. If it is, it
checks if all the features with biotype 'LRG' are mapped to the lrg coordinate system. Then it checks
if all the features mapped on the lrg coordinate system have the biotype 'LRG'.

Perl implementation of LRG.java test.
See: https://github.com/Ensembl/ensj-healthcheck/blob/26644ee7982be37aef610afc69fae52cc70f5b35/src/org/ensembl/healthcheck/testcase/generic/LRG.java

=cut

#!/usr/bin/env perl

use strict;
use warnings;

use File::Spec;
use Getopt::Long;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Utils::SqlHelper;

use Logger;

my $registry = 'Bio::EnsEMBL::Registry';

my $parent_dir = File::Spec->updir;
my $file = $parent_dir . "/config";

my $species;

my $config = do $file;
if(!$config){
    warn "couldn't parse $file: $@" if $@;
    warn "couldn't do $file: $!"    unless defined $config;
    warn "couldn't run $file"       unless $config; 
}
else {
    $registry->load_registry_from_db(
        -host => $config->{'db_registry'}{'host'},
        -user => $config->{'db_registry'}{'user'},
        -port => $config->{'db_registry'}{'port'},
    );
    #if there is command line input use that, else take the config file.
    GetOptions('species:s' => \$species);
    if(!defined $species){
        $species = $config->{'species'};
    }
} 

my $log = Logger->new({
    healthcheck => 'LRG',
    type => 'core',
    species => $species,
});


#only applies to core databases
my $dba = $registry->get_DBAdaptor($species, 'core');

my $helper = Bio::EnsEMBL::Utils::SqlHelper->new(
    -DB_CONNECTION => $dba->dbc()
);

my $result = 1;

if(assert_lrgs($helper)){
    $result &= assert_lrg_annotations($helper, 'gene');
    $result &= assert_lrg_annotations($helper, 'transcript');
}
else{
     $log->message("SKIPPING: No LRG seq_regions found for $species; skipping the test");
}

$log->result($result);

=head2 assert_lrgs

  ARG[$helper]    : Bio::EnsEMBL::Utils::SqlHelper instance

Retrieves the number of sequence regions mapped on the lrg coordinate system. Returns true if
there are one or more sequence regions.

=cut

sub assert_lrgs{
    my ($helper) = @_;

    #retrieves the number of sequence regions that are mapped on the LRG coordinate system.
    my $assert_sql = "SELECT count(sr.seq_region_id) FROM coord_system cs
                         JOIN seq_region sr USING (coord_system_id)
                         WHERE cs.name = 'lrg'";

    my $count_ref = $helper->execute(
                        -SQL => $assert_sql,
                        );


    my $count = $count_ref->[0][0];

    if($count){ 
        return 1;
    }
    return 0;
}

=head2 assert_lrg_annotations

  ARG[$helper]    : Bio::EnsEMBL::Utils::SqlHelper instance.
  ARG[$feature]   : String - name of the feature to test on.

Checks if all the features with biotype 'LRG' are mapped to the lrg coordinate system. Then it checks
if all the features mapped on the lrg coordinate system have the biotype 'LRG'.

=cut

sub assert_lrg_annotations{
    my ($helper, $feature) = @_;

    my $result = 1;
    #Retrieve all the coordinate systems with that have sequences with features that have biotype LRG.
    my $lrg_coord_systems_sql = "SELECT cs.name, count(*) FROM coord_system cs
                                        JOIN seq_region sr USING (coord_system_id)
                                        JOIN $feature f using (seq_region_id)
                                        WHERE f.biotype LIKE 'LRG%'
                                     GROUP BY cs.name";

    my $lrg_coord_systems = $helper->execute(
                                        -SQL => $lrg_coord_systems_sql,
                                    );

    #cast the arrayref into an array (it's easier)
    my @lrg_coord_systems = @{ $lrg_coord_systems };

    my $lrg_present = 0;

    foreach my $coord_system (@lrg_coord_systems){
        #look if we can find the lrg coordinate system somewhere in the results.
        if (grep {$_ eq 'lrg'} @{ $coord_system }){
            $lrg_present = 1;
        }   
    }
    if(!$lrg_present){
        log->message("PROBLEM: lrg coordinate system exists but no $feature(s) are attached");
        $result = 0;
    }
    
    #loop over the result set of coordinate systems that have features with biotype lrg    
    for(my $i = 0; $i < @lrg_coord_systems; $i++){
        #get the coordinate system name
        if (defined($lrg_coord_systems[$i][0])){
            my $coord_system = $lrg_coord_systems[$i][0];
            #if the coordinate system is not lrg it should not have features with biotype lrg attached!
            if ($coord_system ne 'lrg'){
                log->message("PROBLEM: LRG biotyped $feature(s) attached to the wrong coordinate system: " 
                      . ($lrg_coord_systems[$i][0]));
                $result = 0;
            }
        }
    }

    
    #now retrieve all the biotypes of all the features that are mapped on the lrg coordinate system.
    my $lrg_biotypes_sql = "SELECT f.biotype, count(*) FROM coord_system cs
                                        JOIN seq_region sr USING (coord_system_id)
                                        JOIN $feature f USING (seq_region_id)
                                        WHERE cs.name = 'lrg'
                                    GROUP BY f.biotype";

    my $lrg_biotypes = $helper->execute(
                                    -SQL => $lrg_biotypes_sql,
                        );

    #cast ref into an array
    my @lrg_biotypes = @{ $lrg_biotypes };
     
    #iterate over all the biotypes that are mapped on the lrg coordinate system
    for(my $i = 0; $i < @lrg_biotypes; $i++){
        #retrieve the biotype name
        if (defined($lrg_biotypes[$i][0])){
            my $biotype = $lrg_biotypes[$i][0];
            #if the biotype name isn't associated with LRG it shouldn't be on the lrg coordinate system!
            if(index($biotype, 'LRG') == -1){
                log->message("PROBLEM: lrg coordinate system has the following wrongly biotyped $feature(s) "
                      . "attached to it: $biotype");
                $result = 0;
            }
        }
    }
    
    return $result;

}


