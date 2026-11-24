-- m_radarmulta | contas de área (usado no servidor e no client) - mesma lógica do m_territorios
-- Um radar é um CÍRCULO (centro + raio) ou uma ÁREA DESENHADA (pontos = cantos do polígono).

Area = {}

-- ponto (x, y) dentro do polígono? (ray casting)
function Area.dentroPoligono(pontos, x, y)
    local dentro = false
    local j = #pontos
    for i = 1, #pontos do
        local xi, yi, xj, yj = pontos[i].x, pontos[i].y, pontos[j].x, pontos[j].y
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
            dentro = not dentro
        end
        j = i
    end
    return dentro
end

function Area.ehPoligono(t)
    return type(t.pontos) == 'table' and #t.pontos >= 3
end

-- pos (x, y) dentro do território?
function Area.dentro(t, pos)
    if Area.ehPoligono(t) then return Area.dentroPoligono(t.pontos, pos.x, pos.y) end
    local dx, dy = pos.x - t.centro.x, pos.y - t.centro.y
    return dx * dx + dy * dy <= t.raio * t.raio
end

-- meio do polígono (média dos cantos) - usado pro blip e pro debug
function Area.centro(pontos)
    local x, y, z = 0.0, 0.0, 0.0
    for _, p in ipairs(pontos) do x, y, z = x + p.x, y + p.y, z + (p.z or 0.0) end
    local n = #pontos
    return vec3(x / n, y / n, z / n)
end

-- maior distância do meio até um canto (tamanho aproximado da área)
function Area.raioMaximo(pontos, centro)
    local r = 0.0
    for _, p in ipairs(pontos) do
        local dx, dy = p.x - centro.x, p.y - centro.y
        r = math.max(r, math.sqrt(dx * dx + dy * dy))
    end
    return r
end

-- área em m² (pra mostrar no painel)
function Area.tamanho(pontos)
    local soma = 0.0
    local j = #pontos
    for i = 1, #pontos do
        soma = soma + (pontos[j].x + pontos[i].x) * (pontos[j].y - pontos[i].y)
        j = i
    end
    return math.abs(soma / 2)
end
