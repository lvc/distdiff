function show_item(item)
{
    item.style.display = '';
    item.style.visibility = 'visible';
}
function hide_item(item)
{
    item.style.display = 'none';
    item.style.visibility = 'hidden';
}

function applyFilter(table_id)
{
    var table = document.getElementById(table_id);
    var sfilt = document.getElementById('sfilt').value;
    for (var i = 0; row = table.rows[i]; i++)
    {
        var status = row.cells[1].innerHTML;
        if(row.id=='topHeader')
            continue;
        var show = 1;
        if(sfilt!='all' && sfilt!=status) {
            show = 0;
        }
        if(show==1) {
            show_item(row);
        }
        else {
            hide_item(row);
        }
    }
}