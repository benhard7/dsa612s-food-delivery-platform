# Checks that lifecycle events and direct requests turn into notifications.
# Needs: docker compose up -d kafka kafka-init mongo, plus order (:9001), restaurant (:9002),
#        payment (:9003) AND notification (:9005) services running.
param(
    [string]$OrderBase = "http://localhost:9001",
    [string]$RestBase  = "http://localhost:9002",
    [string]$NotBase   = "http://localhost:9005"
)
$ErrorActionPreference = "Stop"

function PostJson($url, $obj) { Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body ($obj | ConvertTo-Json -Depth 5) }
function Show($orderId) {
    $n = @(Invoke-RestMethod "$NotBase/notifications?orderId=$orderId")
    "($($n.Count) notifications)"
    $n | Format-Table source, recipientType, channel, status, message -AutoSize -Wrap
}

"--- set up restaurant ---"
$rest = PostJson "$RestBase/restaurants" @{ name = "Kapana Corner"; address = "Katutura, Windhoek"; openTime = "08:00"; closeTime = "22:00" }
$rid = $rest.restaurantId
PostJson "$RestBase/restaurants/$rid/menu" @{ itemId = "m-1"; name = "Kapana"; price = 40.0; stock = 20 } | Out-Null

"--- place an order, let it be paid and confirmed ---"
$o = PostJson "$OrderBase/orders" @{
    customerId = "cust-45"; restaurantId = $rid
    items = @(@{ itemId = "m-1"; name = "Kapana"; qty = 2; price = 40.0 })
    deliveryAddress = "12 Independence Ave, Windhoek"
}
Start-Sleep 6
"expect 4: created, payment, confirmed (customer) + 'new confirmed order' (restaurant, from Restaurant Service)"
Show $o.orderId

"--- cancel it ---"
Invoke-RestMethod -Method Post -Uri "$OrderBase/orders/$($o.orderId)/cancel" | Out-Null
Start-Sleep 5
"expect 7: + cancelled (customer + restaurant) + refund notice (from Payment Service)"
Show $o.orderId

"--- direct request through the REST API ---"
PostJson "$NotBase/notifications" @{ recipientType = "DRIVER"; recipientId = "drv-1"; channel = "SMS"; message = "Shift starts at 17:00"; orderId = $o.orderId } | Out-Null
Start-Sleep 3
"expect the DRIVER SMS to appear:"
Invoke-RestMethod "$NotBase/notifications?recipientType=DRIVER&orderId=$($o.orderId)" | Format-Table source, recipientId, channel, status, message -AutoSize

"--- invalid channel is rejected ---"
try {
    PostJson "$NotBase/notifications" @{ recipientType = "DRIVER"; recipientId = "drv-1"; channel = "PIGEON"; message = "hi" } | Out-Null
    "unexpectedly accepted"
} catch {
    "HTTP $($_.Exception.Response.StatusCode.value__)   (expect 400)"
}
