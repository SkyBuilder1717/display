<?php
header('Content-Type: application/json');

$url = $_GET['url'] ?? '';

if ($url === '') {
    echo json_encode(["error" => "missing url"]);
    exit;
}

$tmp = tempnam(sys_get_temp_dir(), "img");

$content = @file_get_contents($url);
if ($content === false) {
    echo json_encode(["error" => "invalid url"]);
    unlink($tmp);
    exit;
}

file_put_contents($tmp, $content);

$info = getimagesize($tmp);
if ($info === false) {
    echo json_encode(["error" => "invalid image"]);
    unlink($tmp);
    exit;
}

$mime = $info['mime'];
switch ($mime) {
    case 'image/png':
        $im = imagecreatefrompng($tmp);
        break;
    case 'image/jpeg':
    case 'image/jpg':
        $im = imagecreatefromjpeg($tmp);
        break;
    default:
        echo json_encode(["error" => "unsupported format"]);
        unlink($tmp);
        exit;
}

$w = imagesx($im);
$h = imagesy($im);

$max = 128;
if ($w > $max || $h > $max) {
    $scale = min($max / $w, $max / $h);
    $new_w = max(1, floor($w * $scale));
    $new_h = max(1, floor($h * $scale));
    $resized = imagecreatetruecolor($new_w, $new_h);
    imagealphablending($resized, false);
    imagesavealpha($resized, true);
    imagecopyresampled($resized, $im, 0, 0, 0, 0, $new_w, $new_h, $w, $h);
    imagedestroy($im);
    $im = $resized;
    $w = $new_w;
    $h = $new_h;
}

$truecolor = imagecreatetruecolor($w, $h);
imagesavealpha($truecolor, true);
$trans = imagecolorallocatealpha($truecolor, 0, 0, 0, 127);
imagefill($truecolor, 0, 0, $trans);
imagecopy($truecolor, $im, 0, 0, 0, 0, $w, $h);
imagedestroy($im);

$pixels = [];
for ($y = 0; $y < $h; $y++) {
    for ($x = 0; $x < $w; $x++) {
        $col = imagecolorat($truecolor, $x, $y);
        $r = ($col >> 16) & 0xFF;
        $g = ($col >> 8) & 0xFF;
        $b = $col & 0xFF;
        $a = 127 - (($col & 0x7F000000) >> 24);
        $a = round($a * 2);
        $pixels[] = [$r, $g, $b, $a];
    }
}
imagedestroy($truecolor);
unlink($tmp);

echo json_encode([
    "width" => $w,
    "height" => $h,
    "pixels" => $pixels
]);