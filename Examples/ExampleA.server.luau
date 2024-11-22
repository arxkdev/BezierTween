local Bezier = require(game:GetService("ReplicatedStorage"):WaitForChild("BezierTween"));

local NewBezier = Bezier.new(
	workspace["ExampleA"].P1,
	workspace["ExampleA"].P2,
	workspace["ExampleA"].P3,
	workspace["ExampleA"].P4
);

local NumPoints = 50;
local Points = {};
local Lines = {};

for _ = 1, NumPoints do
	local TargetPart = Instance.new("Part");
	TargetPart.Size = Vector3.new(0.75, 0.75, 3);
	TargetPart.BrickColor = BrickColor.new("Really red");
	TargetPart.CanCollide = false;
	TargetPart.Anchored = true;
    TargetPart.Parent = workspace;
	table.insert(Points, TargetPart);
end

for _ = 1, NumPoints - 1 do
	local TargetPart = Instance.new("Part");
	TargetPart.Size = Vector3.new(0.5, 0.5, 1);
	TargetPart.BrickColor = BrickColor.new("Black");
	TargetPart.CanCollide = false;
	TargetPart.Anchored = true;
    TargetPart.Parent = workspace;
	table.insert(Lines, TargetPart);
end

while (task.wait()) do
	for i = 1, #Points do
		local t = (i - 1) / (#Points - 1);
		local Position = NewBezier:CalculatePositionAt(t);
		local Derivative = NewBezier:CalculateDerivativeAt(t);
		Points[i].CFrame = CFrame.new(Position, Position + Derivative);
	end;

	for i = 1, #Lines do
		local Line = Lines[i];
		local p1, p2 = Points[i].Position, Points[i + 1].Position;
		Line.Size = Vector3.new(Line.Size.X, Line.Size.Y, (p2 - p1).Magnitude);
		Line.CFrame = CFrame.new(0.5 * (p1 + p2), p2);
	end;
end