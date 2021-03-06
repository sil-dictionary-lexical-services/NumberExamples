#!/usr/bin/perl
# perl ./hackFWvariants.pl

my $debug=0;
my $checktags=0; #Stop after checking the validity of the tags

use 5.016;
use strict;
use warnings;
use English;
use Data::Dumper qw(Dumper);
use utf8;

use open qw/:std :utf8/;
use XML::LibXML;

use Config::Tiny;
my $configfile = 'PromoteSubentries.ini';
 # ; PromoteSubentries.ini file looks like:
 # [Var2Compform]
 # FwdataIn=FwProject-before.fwdata
 # FwdataOut=FwProject.fwdata
 # modeltag1=Model Unspecified Complex Entry
 # modifytag1=Complex_Form
 # the modeltag and modifytag lines are repeated as needed
 # numberofmodels=1

my $inisection = 'Var2Compform';
my $config = Config::Tiny->read($configfile, 'crlf');
#ToDo: should also use Getopt::Long instead of setting variables as above
#ToDo: get the pathname of the INI file from $0 so that the two go together
die "Couldn't find the INI file:$configfile\nQuitting" if !$config;
my $infilename = $config->{$inisection}->{FwdataIn};
my $outfilename = $config->{$inisection}->{FwdataOut};

my $lockfile = $infilename . '.lock' ;
die "A lockfile exists: $lockfile\
Don't run $0 when FW is running.\
Run it on a copy of the project, not the original!\
I'm quitting" if -f $lockfile ;

my $modelmax= $config->{$inisection}->{numberofmodels};
die "numberofmodels not specified" if !defined $modelmax;
my $modeltag;
my $modifytag;
my $modelcount;
for ($modelcount =1; $modelcount <=$modelmax; $modelcount++) {
	$modeltag = $config->{$inisection}->{"modeltag$modelcount"};
	$modifytag = $config->{$inisection}->{"modifytag$modelcount"};
	if ( (!defined $modeltag) || (!defined $modifytag)) {
		say STDERR "Skipping Model #$modelcount";
		delete $config->{$inisection}->{"modeltag$modelcount"};
		delete $config->{$inisection}->{"modifytag$modelcount"};
		next;
		}

	if ( (index($modeltag, $modifytag) != -1) or  (index($modifytag, $modeltag) != -1)) {
	# use index because Xpath doesn't use regex and we use Xpath to query the FW project
		say STDERR "Use different tags for modeltag and modifytag. One contains the other.";
		say STDERR "modeltag$modelcount=", $modeltag;
		say STDERR "modifytag$modelcount=", $modifytag;
		say STDERR "Ignoring entry #$modelcount";
		delete $config->{$inisection}->{"modeltag$modelcount"};
		delete $config->{$inisection}->{"modifytag$modelcount"};
		}
	}

#Check the modifytag against all the others
for ($modelcount =1; $modelcount <=$modelmax; $modelcount++) {
	$modeltag = $config->{$inisection}->{"modeltag$modelcount"};
	$modifytag = $config->{$inisection}->{"modifytag$modelcount"};
	next if ( (!defined $modeltag) || (!defined $modifytag));
	for (my $chckcount =1; $chckcount <=$modelmax; $chckcount++) {
		next if $chckcount == $modelcount;
		my $chckmodel = $config->{$inisection}->{"modeltag$chckcount"};
		next if !defined $chckmodel;
		my $chckmodify = $config->{$inisection}->{"modifytag$chckcount"};
		next if !defined $chckmodify;
		if ( (index($chckmodel, $modifytag) != -1) or (index($modifytag, $chckmodel) != -1)) {
			say STDERR "Use different tags for modeltags and modifytags. One contains the other.";
			say STDERR "modeltag$chckcount=", $chckmodel;
			say STDERR "modifytag$modelcount=", $modifytag;
			say STDERR "Ignoring entry #$modelcount";
			delete $config->{$inisection}->{"modeltag$modelcount"};
			delete $config->{$inisection}->{"modifytag$modelcount"};
			}
		if ( (index($chckmodify, $modifytag) != -1) or (index($modifytag, $chckmodify) != -1)) {
			say STDERR "Modifytags should be unique One contains the other.";
			say STDERR "modifytag$modelcount=", $modifytag;
			say STDERR "modifytag$chckcount=", $chckmodify;
			say STDERR "Ignoring entry #$modelcount";
			delete $config->{$inisection}->{"modeltag$modelcount"};
			delete $config->{$inisection}->{"modifytag$modelcount"};
			}
		}
	}

die "config:". Dumper($config) if $checktags;
say "Processing fwdata file: $infilename";

my $fwdatatree = XML::LibXML->load_xml(location => $infilename);

my %rthash;
foreach my $rt ($fwdatatree->findnodes(q#//rt#)) {
	my $guid = $rt->getAttribute('guid');
	$rthash{$guid} = $rt;
	}
for ($modelcount =1; $modelcount <=$modelmax; $modelcount++) {
	$modeltag = $config->{$inisection}->{"modeltag$modelcount"};
	$modifytag = $config->{$inisection}->{"modifytag$modelcount"};
	next if ( (!defined $modeltag) || (!defined $modifytag));
	say "modeltag$modelcount=", $modeltag if $debug;
	say "modifytag$modelcount=", $modifytag if $debug;

	my ($modelTextrt) = $fwdatatree->findnodes(q#//*[contains(., '# . $modeltag . q#')]/ancestor::rt#);
	if (!$modelTextrt) {
		say STDERR "";
		say STDERR  "The model #$modelcount, \"$modeltag\" isn't in any records";
		say  "The model #$modelcount, \"$modeltag\" was not processed. Check error listing";
		next;
		}
	# say  rtheader($modelTextrt) ;

	my ($modelOwnerrt) = traverseuptoclass($modelTextrt, 'LexEntry');
	if ($modelOwnerrt->getAttribute('class') ne 'LexEntry') {
		say STDERR "";
		say STDERR "The first time that Model #$modelcount, \"$modeltag\" was found, it was in a record that's not a  Lexical Entry. Model #$modelcount will be ignored.";
		say "The model #$modelcount, \"$modeltag\" was not processed. Check the error listing.";
		next;
		}
	say ""; say "For the model #$modelcount, using tag:\"$modeltag\", found the tag in the entry:";
	say "    ", displaylexentstring($modelOwnerrt);

	my $modelentryref = $rthash{$modelOwnerrt->findvalue('./EntryRefs/objsur/@guid')};
	my $modelEntryTypeName;
	if ($modelentryref) {
		# Fetch the name of the ComplexEntryType that the model uses
		my $modelEntryTypert = $rthash{$modelentryref->findvalue('./ComplexEntryTypes/objsur/@guid')};
		$modelEntryTypeName = $modelEntryTypert->findvalue('./Name/AUni'); 
		say "It has a \"$modelEntryTypeName\" EntryType";
		}
	else {
		say "The model entry with the tag:$modeltag doesn't refer to another entry. Check that entry in the FLEx database.";
		say "Ignoring that tag";
		next;
	}
	my ($modelHideMinorEntryval) = $modelentryref->findvalue('./HideMinorEntry/@val');
	my ($modelRefTypeval) = $modelentryref->findvalue('./RefType/@val');
	my $modelComplexEntryTypesstring= ($modelentryref->findnodes('./ComplexEntryTypes'))[0]->toString;
	$modelComplexEntryTypesstring =~ m/guid=\"(.*?)\"/;
	my $modelCETguid = $1;
	my ($modelHasAPrimaryLexemes) = $modelentryref->findnodes('./PrimaryLexemes') ;
	my ($modelHasAShowComplexFormsIn) = $modelentryref->findnodes('./ShowComplexFormsIn');
=pod
	say 'Found the model stuff:';
	say 'HideMinorEntry val:', $modelHideMinorEntryval;
	say 'RefType val:', $modelRefTypeval;
	say 'ComplexEntryTypes (string):', $modelComplexEntryTypesstring;
	say 'Has a PrimaryLexemes' if $modelHasAPrimaryLexemes;
	say 'Has a ShowComplexFormsIn' if $modelHasAShowComplexFormsIn;
	say 'End of the model stuff:';
=cut

	my @modifyrts = $fwdatatree->findnodes(q#//*[contains(., '# . $modifytag . q#')]/ancestor::rt#);
	say "Searching for entries containing \"$modifytag\", found ", scalar @modifyrts, " records";
	say '';
	my $modifycount = 0;
	foreach my $seToModifyTextrt (@modifyrts) {
		my ($seModifyOwnerrt) = traverseuptoclass($seToModifyTextrt, 'LexEntry'); 
		$modifycount++;
		if ($seModifyOwnerrt->getAttribute('class') ne 'LexEntry') {
			say STDERR "";
			say STDERR "Model #$modelcount, Entry #$modifycount,\"$modifytag\"  wasn't in a Lexical Entry. It will be ignored.";
			say "Model #$modelcount, Entry #$modifycount,\"$modifytag\" was not processed. Check the error listing";
			next;
			}
		say  "Model #$modelcount, Entry #$modifycount, modifying to a \"$modelEntryTypeName\" for:";
		say "    ", displaylexentstring($seModifyOwnerrt);
		if (!$seModifyOwnerrt->findvalue('./EntryRefs/objsur/@guid')) {
			say STDERR "Model #$modelcount, Entry #$modifycount, Tag \"$modifytag\" is a main entry (no EntryRefs):";
			say STDERR "    ", displaylexentstring($seModifyOwnerrt);
			say "No changes made to that entry see error log.";
			next;
			}
		my $entryreftomodify = $rthash{$seModifyOwnerrt->findvalue('./EntryRefs/objsur/@guid')};
		# say "EntryRefToModify Before: $entryreftomodify" if $debug;
		if (!$entryreftomodify->findnodes('./ComponentLexemes')) {
			say STDERR "Found \"$modifytag\" but no Component Lexemes in :";
			say STDERR "    ", displaylexentstring($seModifyOwnerrt);
			next;
			}

		# New nodes are built from strings and inserted in order
		my $newnode = XML::LibXML->load_xml(string => $modelComplexEntryTypesstring)->findnodes('//*')->[0];
		# the above expression makes a new tree from the model ComplexEntryTypestring

		if (my ($CETnode) = $entryreftomodify->findnodes('./ComplexEntryTypes')) {
			say "Entry #$modifycount already has Complex type(s)";
			my $CETguids= $entryreftomodify->findvalue('./ComplexEntryTypes/objsur/@guid');
			# All the guids concatenated
			say "CET guids:", $CETguids if $debug;
			say "model guid:", $modelCETguid if $debug;
			say "CET node", $CETnode if $debug;
			if ($CETguids =~ m/$modelCETguid/) {
				say "    and \"$modelEntryTypeName\" is already in the list";
				}
			else {
				my ($newCETobjsur) = $newnode->findnodes('./objsur');
				$CETnode->appendChild($newCETobjsur);
				say "    Added \"$modelEntryTypeName\" to the list";
				say "CET node", $CETnode if $debug;
				}
			next;
			}

		$entryreftomodify->insertBefore($newnode, ($entryreftomodify->findnodes('./ComponentLexemes'))[0]);

		# Additional new nodes use the objsur@guid from the ComponentLexemes
		# Stringify the ComponentLexemes node, change the tags, nodify the changed string and put the new node in its place
		my ($CLstring) = ($entryreftomodify->findnodes('./ComponentLexemes'))[0]->toString;
		my $tempstring = $CLstring;
		if ($modelHasAPrimaryLexemes)  {
			$tempstring =~ s/ComponentLexemes/PrimaryLexemes/g;
			$newnode = XML::LibXML->load_xml(string => $tempstring)->findnodes('//*')->[0];
			$entryreftomodify->insertBefore($newnode, ($entryreftomodify->findnodes('./RefType'))[0]);
			}
		$tempstring = $CLstring;
		if ($modelHasAShowComplexFormsIn)  {
			$tempstring =~ s/ComponentLexemes/ShowComplexFormsIn/g;
			$newnode = XML::LibXML->load_xml(string => $tempstring)->findnodes('//*')->[0];
			$entryreftomodify->insertAfter($newnode, ($entryreftomodify->findnodes('./RefType'))[0]);
			}

		# Attribute values are done in place
		(my $attr) = $entryreftomodify->findnodes('./HideMinorEntry/@val');
		$attr->setValue($modelHideMinorEntryval) if $attr;
		($attr) = $entryreftomodify->findnodes('./RefType/@val');
		$attr->setValue($modelRefTypeval) if $attr;

		# remove the VariantEntryTypes (VET) node if it's there
		my ($VETnode) = $entryreftomodify->findnodes('./VariantEntryTypes') ;
			$VETnode->parentNode->removeChild($VETnode) if $VETnode ;
=pod
		say "";
		say "EntryRefToModify  After: ", $entryreftomodify ;
		say "";
		say "";
=cut
	}

}

my $xmlstring = $fwdatatree->toString;
# Some miscellaneous Tidying differences
$xmlstring =~ s#><#>\n<#g;
$xmlstring =~ s#(<Run.*?)/\>#$1\>\</Run\>#g;
$xmlstring =~ s#/># />#g;
say "";
say "Finished processing, writing modified  $outfilename" ;
open my $out_fh, '>:raw', $outfilename;
print {$out_fh} $xmlstring;


# Subroutines
sub rtheader { # dump the <rt> part of the record
my ($node) = @_;
return  ( split /\n/, $node )[0];
}

sub traverseuptoclass { 
	# starting at $rt
	#    go up the ownerguid links until you reach an
	#         rt @class == $rtclass
	#    or 
	#         no more ownerguid links
	# return the rt you found.
my ($rt, $rtclass) = @_;
	while ($rt->getAttribute('class') ne $rtclass) {
#		say ' At ', rtheader($rt);
		if ( !$rt->hasAttribute('ownerguid') ) {last} ;
		# find node whose @guid = $rt's @ownerguid
		$rt = $rthash{$rt->getAttribute('ownerguid')};
	}
#	say 'Found ', rtheader($rt);
	return $rt;
}

sub displaylexentstring {
my ($lexentrt) = @_;

my ($formguid) = $lexentrt->findvalue('./LexemeForm/objsur/@guid');
my $formrt =  $rthash{$formguid};
my ($formstring) =($rthash{$formguid}->findnodes('./Form/AUni/text()'))[0]->toString;
# If there's more than one encoding, you only get the first

my ($homographno) = $lexentrt->findvalue('./HomographNumber/@val');

my $guid = $lexentrt->getAttribute('guid');
return qq#$formstring # . ($homographno ? qq#hm:$homographno #  : "") . qq#(guid="$guid")#;
}
