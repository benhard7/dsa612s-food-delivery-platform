# End-to-end test: Order <-> Payment <-> Restaurant through Kafka.
# Needs: docker compose up -d kafka kafka-init mongo, plus order (:9001), restaurant (:9002) AND payment (:9003) services running.
param(
    [string]$OrderBase = "http://localhost:9001",
    [string]$RestBase  = "http://localhost:9002",
    [string]$PayBase   = "http://localhost:9003"
)
$ErrorActionPreference = "Stop"   # stop at the first real error instead of continuing with blank values

function PostJson($url, $obj) { Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body ($obj | ConvertTo-Json -Depth 5) }
function NewOrder($rid, $qty) {
    PostJson "$OrderBase/orders" @{
        customerId = "cust-45"; restaurantId = $rid
        items = @(@{ itemId = "m-1"; name = "Kapana"; qty = $qty; price = 40.0 })
        deliveryAddress = "12 Independence Ave, Windhoek"
    }
}
function OrderStatus($id)   { (Invoke-RestMethod "$OrderBase/orders/$id").status }
function PayStatus($id)     { (Invoke-RestMethod "$PayBase/payments?orderId=$id").status }
function KitchenStatus($id) { (Invoke-RestMethod "$RestBase/kitchen/orders/$id").status }

"--- set up a restaurant with 10 Kapana in stock ---"
$rest = PostJson "$RestBase/restaurants" @{ name = "Kapana Corner"; address = "Katutura, Windhoek"; openTime = "08:00"; closeTime = "22:00" }
$rid = $rest.restaurantId
PostJson "$RestBase/restaurants/$rid/menu" @{ itemId = "m-1"; name = "Kapana"; price = 40.0; stock = 10 } | Out-Null
# Windows PowerShell 5.1 passes a JSON array down the pipeline as ONE object, so assign it first, then pipe.
function Stock { $items = Invoke-RestMethod "$RestBase/restaurants/$rid/menu"; ($items | Where-Object { $_.itemId -eq "m-1" }).stock }
"restaurant $rid  openNow=$($rest.openNow)  stock=$(Stock)"

"--- order 2 Kapana ---"
$o1 = NewOrder $rid 2
Start-Sleep 5
"order   -> $(OrderStatus $o1.orderId)   (expect CONFIRMED)"
"payment -> $(PayStatus $o1.orderId)   (expect COMPLETED)"
"kitchen -> $(KitchenStatus $o1.orderId)   (expect CONFIRMED)"
"stock   -> $(Stock)   (expect 8)"

"--- kitchen works on it ---"
Invoke-RestMethod -Method Post -Uri "$RestBase/kitchen/orders/$($o1.orderId)/preparing" | Out-Null; Start-Sleep 2
"order   -> $(OrderStatus $o1.orderId)   (expect PREPARING)"
Invoke-RestMethod -Method Post -Uri "$RestBase/kitchen/orders/$($o1.orderId)/ready" | Out-Null; Start-Sleep 2
"order   -> $(OrderStatus $o1.orderId)   (expect READY)"

"--- order 20 Kapana (only 8 left) ---"
$o2 = NewOrder $rid 20
Start-Sleep 6
"kitchen -> $(KitchenStatus $o2.orderId)   (expect REJECTED)"
"order   -> $(OrderStatus $o2.orderId)   (expect CANCELLED)"
"payment -> $(PayStatus $o2.orderId)   (expect REFUNDED, or FAILED if over the payment limit)"
"stock   -> $(Stock)   (expect 8, unchanged)"

"--- cancel the first order -> stock comes back ---"
Invoke-RestMethod -Method Post -Uri "$OrderBase/orders/$($o1.orderId)/cancel" | Out-Null
Start-Sleep 4
"kitchen -> $(KitchenStatus $o1.orderId)   (expect CANCELLED)"
"stock   -> $(Stock)   (expect 10)"
