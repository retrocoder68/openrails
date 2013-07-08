﻿// COPYRIGHT 2013 by the Open Rails project.
// 
// This file is part of Open Rails.
// 
// Open Rails is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// Open Rails is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with Open Rails.  If not, see <http://www.gnu.org/licenses/>.

using System;
using System.Collections;
using System.IO;

namespace MSTS
{
    /// <summary>
    /// Work with engine files
    /// </summary>
    public class ENGFile
    {
        public string Name = "";
        public string Description = "";

        public ENGFile(string filePath)
        {
            Name = Path.GetFileNameWithoutExtension(filePath);
            using (var stf = new STFReader(filePath, false))
                stf.ParseFile(new STFReader.TokenProcessor[] {
                    new STFReader.TokenProcessor("engine", ()=>{
                        stf.ReadString();
                        stf.ParseBlock(new STFReader.TokenProcessor[] {
                            new STFReader.TokenProcessor("name", ()=>{ Name = stf.ReadStringBlock(""); }),
                            new STFReader.TokenProcessor("description", ()=>{ Description = stf.ReadStringBlock(""); }),
                        });
                    }),
                });
        }

        public override string ToString()
        {
            return Name;
        }
    }
}
