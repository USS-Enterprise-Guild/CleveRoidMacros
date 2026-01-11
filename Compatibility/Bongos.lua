CleveRoids.RegisterActionEventHandler(function(slot, event)
    if not slot or not BActionButton or not BActionBar then return end

    local button = getglobal(format("BActionButton%d", slot))
    if button then
        BActionButton.Update(button)
    end
end)
