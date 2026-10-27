use strict;
use warnings;
use utf8;
use File::Find;
binmode STDOUT, ':encoding(UTF-8)';
my $pattern = shift @ARGV;
my $regex = eval { qr/$pattern/ };
die "[localization-search] invalid regex: $@" if $@;
my @files;
for my $root (@ARGV) {
    if (-f $root) { push @files, $root; }
    elsif (-d $root) { find({ wanted => sub { push @files, $File::Find::name if -f $_ && /\.swift$/ }, no_chdir => 1 }, $root); }
    else { die "[localization-search] missing path: $root\n"; }
}
my $matched = 0;
for my $file (sort @files) {
    open my $input, '<:encoding(UTF-8)', $file or die "[localization-search] $file: $!\n";
    my $line = 0;
    while (my $text = <$input>) {
        ++$line;
        if ($text =~ $regex) { print "$file:$line:$text"; $matched = 1; }
    }
    close $input or die "[localization-search] $file: $!\n";
}
exit($matched ? 0 : 1);
