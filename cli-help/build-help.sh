packageDir="$(echo $0 | rev | cut -d'/' -f3- | rev)"
destination="$packageDir/cli-help"

declare -a array=("aws-deploy" "build" "publish" "invoke" "build-and-publish")
arraylength=${#array[@]}

for (( i=0; i<${arraylength}; i++ ));
do
   item="${array[$i]}"
   file="$destination/0$i-$item.md"
   echo '```swift' > $file
   swift run --package-path "$packageDir" $command --help >> $file
   echo '```' >> $file
done
